#!/usr/bin/env python3
"""Read Databases.xlsx and emit redacted, repeatable SQL for REVIEW staging only."""
import argparse, collections, datetime as dt, decimal, hashlib, json, pathlib, re
from zoneinfo import ZoneInfo
import openpyxl

KEYS={'Thông tin dự án':'PropertyID','Nhân viên':'Email','Contracts':'PhoneID','Historical':'History_ID','Attachments':'attachmentID','clicks':'ID','Phường':'ID','Loại Hình':'TypeID','Loại dự án':'TypeID'}
SECRET_KEYS={'password','passwd','pwd'}
VERSION='sgn-stager-1.0.0'
def clean_payload(payload,timezone):
    result={}
    for key,value in payload.items():
        if key.strip().casefold() in SECRET_KEYS: continue
        if isinstance(value,dt.datetime):
            # Source time convention is supplied explicitly, not guessed.
            value=value.replace(tzinfo=timezone).isoformat() if value.tzinfo is None else value.isoformat()
        elif isinstance(value,dt.date): value=value.isoformat()
        result[key]=value
    return result
def js(value): return json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False)
def lit(value): return 'NULL' if value is None else "'"+str(value).replace("'","''")+"'"
def numeric(value):
    if value is None or str(value).strip()=='':return None
    if isinstance(value,(dt.datetime,dt.date,bool)):raise ValueError('Not numeric')
    v=decimal.Decimal(str(value).strip())
    if not v.is_finite():raise ValueError('Not finite')
    return v
def read_book(filename,timezone):
    workbook=openpyxl.load_workbook(filename,read_only=True,data_only=True)
    rows=[]; counts={}
    for sheet in workbook:
        iterator=sheet.iter_rows(values_only=True)
        headers=[str(v).strip() if v is not None else '' for v in next(iterator)]
        count=0
        for row_number,values in enumerate(iterator,2):
            if not any(v is not None and str(v).strip() for v in values):continue
            raw={h:v for h,v in zip(headers,values) if h}
            payload=clean_payload(raw,timezone)
            date_fields=[h for h,v in raw.items() if isinstance(v,(dt.datetime,dt.date))]
            if date_fields:payload['_excel_date_fields']=date_fields
            row_key=raw.get(KEYS.get(sheet.title,''))
            key=str(row_key).strip() if row_key is not None else None
            rows.append({'sheet':sheet.title,'row':row_number,'key':key,'payload':payload,'raw':{k:v for k,v in raw.items() if k.casefold() not in SECRET_KEYS}})
            count+=1
        counts[sheet.title]=count
    workbook.close()
    return rows,counts
def classify(rows):
    props=[r for r in rows if r['sheet']=='Thông tin dự án']
    ids=collections.Counter(r['key'] for r in props if r['key'])
    ward_pairs={(r['payload'].get('Ward'),r['payload'].get('District')) for r in rows if r['sheet']=='Phường'}
    issues=[]
    def issue(row,code,severity,details):issues.append({'sheet':row['sheet'],'row':row['row'],'code':code,'severity':severity,'details':details})
    for r in rows:
        r['disposition']='pending';r['reason']=None
        if r['sheet']=='Thông tin dự án':
            if not r['key']:
                r['disposition']='excluded';r['reason']='Incomplete creator-only row; no physical property data'
                issue(r,'missing_property_id','info',{});continue
            if ids[r['key']]>1:issue(r,'duplicate_property_id','blocking',{'legacy_id':r['key'],'occurrences':ids[r['key']]})
            for field in ['Giá Bán (tỷ Đồng)','Giá Thuê (triệu Đồng)']:
                try:
                    value=numeric(r['raw'].get(field))
                    if value is not None and value<=0:issue(r,'nonpositive_'+field,'warning',{'field':field})
                    if value is not None and field=='Giá Bán (tỷ Đồng)' and value>10000:issue(r,'price_unit_review','blocking',{'field':field})
                except (ValueError,decimal.InvalidOperation):issue(r,'invalid_'+field,'blocking',{'field':field})
            if (r['payload'].get('Phường'),r['payload'].get('Quận')) not in ward_pairs:issue(r,'address_reference_review','warning',{})
        if r['sheet'] in ('Contracts','Historical','Attachments','clicks'):
            field='Dự án' if r['sheet'] in ('Historical','clicks') else 'PropertyID'
            ref=str(r['payload'].get(field) or '').strip()
            if not ref:issue(r,'missing_property_reference','blocking',{})
            elif ref not in ids:issue(r,'unresolved_property_reference','blocking',{'legacy_id':ref})
            elif ids[ref]>1:issue(r,'ambiguous_property_reference','blocking',{'legacy_id':ref})
        if r['sheet']=='Attachments' and not r['payload'].get('URL'):issue(r,'missing_file_path','warning',{})
        if r['sheet']=='Loại dự án' and re.search(r'\d{6,}',str(r['payload'].get('Loại Hình') or '').replace(' ','')):
            issue(r,'contaminated_lookup','blocking',{})
    blocked={(i['sheet'],i['row']) for i in issues if i['severity']=='blocking'}
    for r in rows:
        if (r['sheet'],r['row']) in blocked:
            r['disposition']='quarantined';r['reason']='Resolve source issues before canonical import'
    return issues
def emit_sql(rows,counts,issues,source,args):
    digest=hashlib.sha256(source.read_bytes()).hexdigest()
    org=args.organization_id
    with pathlib.Path(args.output).open('w',encoding='utf-8') as f:
        f.write("-- PRIVATE CUSTOMER DATA: execute via trusted migration connection; do not commit.\n")
        f.write("begin;\nset standard_conforming_strings=on;\n")
        f.write(f"insert into crm_import.batches(organization_id,filename,file_sha256,transform_version,expected_sheet_counts) values({org},{lit(source.name)},{lit(digest)},{lit(VERSION+':'+args.source_timezone)},{lit(js(counts))}::jsonb) on conflict(organization_id,file_sha256) do nothing;\n")
        f.write(f"select 1/(case when transform_version={lit(VERSION+':'+args.source_timezone)} and expected_sheet_counts={lit(js(counts))}::jsonb then 1 else 0 end) from crm_import.batches where organization_id={org} and file_sha256={lit(digest)};\n")
        f.write(f"select set_config('sgn_import.batch_id',id::text,true) from crm_import.batches where organization_id={org} and file_sha256={lit(digest)};\n")
        for offset in range(0,len(rows),500):
            f.write('insert into crm_import.source_rows(organization_id,batch_id,sheet_name,row_number,legacy_id,row_sha256,payload,disposition,disposition_reason) values\n')
            vals=[]
            for r in rows[offset:offset+500]:
                payload=js(r['payload']);row_hash=hashlib.sha256(payload.encode()).hexdigest()
                vals.append(f"({org},current_setting('sgn_import.batch_id')::bigint,{lit(r['sheet'])},{r['row']},{lit(r['key'])},{lit(row_hash)},{lit(payload)}::jsonb,{lit(r['disposition'])},{lit(r['reason'])})")
            f.write(',\n'.join(vals)+"\non conflict(organization_id,batch_id,sheet_name,row_number) do nothing;\n")
        for offset in range(0,len(issues),500):
            f.write('insert into crm_import.issues(organization_id,source_row_id,code,severity,details) values\n')
            vals=[]
            for i in issues[offset:offset+500]:
                source_id=f"(select id from crm_import.source_rows where organization_id={org} and batch_id=current_setting('sgn_import.batch_id')::bigint and sheet_name={lit(i['sheet'])} and row_number={i['row']})"
                vals.append(f"({org},{source_id},{lit(i['code'])},{lit(i['severity'])},{lit(js(i['details']))}::jsonb)")
            f.write(',\n'.join(vals)+'\non conflict(organization_id,source_row_id,code) do nothing;\n')
        f.write('commit;\n')
    return {'source_sha256':digest,'transform_version':VERSION,'source_timezone_assumption':args.source_timezone,'sheet_counts':counts,'total_source_rows':len(rows),'issues':dict(collections.Counter(i['code'] for i in issues)),'dispositions':dict(collections.Counter(r['disposition'] for r in rows)),'password_fields_exported':False,'output_bytes':pathlib.Path(args.output).stat().st_size}
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workbook');parser.add_argument('--organization-id',type=int,required=True)
    parser.add_argument('--source-timezone',required=True,help='Confirm source convention, e.g. Asia/Ho_Chi_Minh')
    parser.add_argument('--output',required=True);parser.add_argument('--summary',required=True)
    args=parser.parse_args()
    if args.organization_id<=0:parser.error('Organization ID must be positive')
    source=pathlib.Path(args.workbook)
    rows,counts=read_book(source,ZoneInfo(args.source_timezone));issues=classify(rows)
    summary=emit_sql(rows,counts,issues,source,args)
    pathlib.Path(args.summary).write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'rows':len(rows),'issues':len(issues),'counts':counts,'password_fields_exported':False},ensure_ascii=False))
if __name__=='__main__':main()
