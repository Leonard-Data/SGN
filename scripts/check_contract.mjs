import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = path.resolve(import.meta.dirname, '..');
const read = name => fs.readFile(path.join(root, name), 'utf8');
const contract = JSON.parse(await read('docs/database-contract.json'));
const catalog = JSON.parse(await read(contract.field_catalog));
for (const filename of [contract.human_contract, contract.column_dictionary, 'AGENTS.md', 'docs/DEPLOYMENT.md', 'tests/SUPABASE_INTEGRATION.md']) {
  await fs.access(path.join(root, filename));
}
const actualTables = [...new Set(catalog.columns.map(c => `${c.table_schema}.${c.table_name}`))].sort();
assert.deepEqual(contract.tables, actualTables, 'Contract table inventory differs from tested catalog');
const migrationFiles = (await fs.readdir(path.join(root, contract.authoritative_migrations))).filter(n => n.endsWith('.sql')).sort();
const migrations = (await Promise.all(migrationFiles.map(n => read(`${contract.authoritative_migrations}/${n}`)))).join('\n');
for (const rpc of contract.rpcs) {
  const definition = new RegExp(`create(?: or replace)? function ${rpc.schema}\\.${rpc.name}\\(([^)]*)\\) returns ([^\\n]+?) language`, 'g');
  const matches = [...migrations.matchAll(definition)];
  assert.ok(matches.length, `Missing RPC ${rpc.name}`);
  const match = matches.at(-1);
  const actual = match[1].split(',').map(p => {
    const [, name, type] = p.trim().match(/^(\S+)\s+(.+)$/);
    return { name, sql_type: type };
  });
  assert.deepEqual(rpc.parameters, actual, `${rpc.name} arguments changed`);
  assert.equal(rpc.returns, match[2], `${rpc.name} return shape changed`);
}
const exposedNames = [...migrations.matchAll(/create(?: or replace)? function crm\.(\w+)\(/g)].map(m => m[1]);
assert.deepEqual([...new Set(exposedNames)].sort(), contract.rpcs.map(r => r.name).sort(), 'Exposed RPC inventory changed');
assert.deepEqual(contract.exposed_schemas, ['crm']);
assert.deepEqual(contract.unexposed_schemas, ['crm_private', 'crm_import']);
const config = await read('supabase/config.toml');
assert.match(config, /^schemas = \["crm"\]$/m, 'Local API must expose only crm');
assert.equal(contract.browser_direct_writes, false);
assert.equal(contract.commission.basis, 'verified_final_sale_price');
assert.equal(contract.commission.payable_trigger, 'deal_close');
console.log(JSON.stringify({ contract_version: contract.contract_version, tables: actualTables.length, fields: catalog.columns.length, exposed_rpcs: contract.rpcs.length, result: 'pass' }));
