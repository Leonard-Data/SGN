'use client'

import { createContext, useContext, useEffect, useMemo, useState } from 'react'

type Locale = 'vi' | 'en'
type Theme = 'light' | 'dark'

const copy = {
  vi: {
    eyebrow: 'Không gian làm việc bất động sản',
    signInTitle: 'Chào mừng trở lại',
    signInDescription: 'Nhập thông tin để truy cập tài khoản của bạn',
    signUpTitle: 'Tạo tài khoản SGN',
    signUpDescription: 'Bắt đầu quản lý bất động sản tập trung hơn',
    email: 'Email', password: 'Mật khẩu', emailPlaceholder: 'ten@vidu.com', passwordPlaceholder: 'Nhập mật khẩu',
    signIn: 'Đăng nhập', signUp: 'Tạo tài khoản', signingIn: 'Đang đăng nhập…', signingUp: 'Đang tạo tài khoản…',
    existing: 'Đã có tài khoản?', newUser: 'Bạn mới dùng SGN?', switchIn: 'Đăng nhập', switchUp: 'Tạo tài khoản',
    checkEmail: 'Hãy kiểm tra hộp thư để xác nhận email, sau đó quay lại đăng nhập.', invalid: 'Email hoặc mật khẩu không hợp lệ.',
    createError: 'Không thể tạo tài khoản. Vui lòng kiểm tra thông tin và thử lại.', unexpected: 'Đã xảy ra lỗi. Vui lòng thử lại.',
  },
  en: {
    eyebrow: 'Your property workspace', signInTitle: 'Welcome back', signInDescription: 'Enter your credentials to access your account',
    signUpTitle: 'Create your SGN account', signUpDescription: 'Start managing your property workspace with clarity',
    email: 'Email', password: 'Password', emailPlaceholder: 'name@example.com', passwordPlaceholder: 'Enter your password',
    signIn: 'Sign in', signUp: 'Create account', signingIn: 'Signing in…', signingUp: 'Creating account…',
    existing: 'Already have an account?', newUser: 'New to SGN?', switchIn: 'Sign in', switchUp: 'Create an account',
    checkEmail: 'Check your inbox to confirm your email, then return here to sign in.', invalid: 'Invalid email or password.',
    createError: 'We could not create your account. Check your details and try again.', unexpected: 'Something went wrong. Please try again.',
  },
} as const

type Copy = (typeof copy)[Locale]
const AppContext = createContext<{ locale: Locale; setLocale: (locale: Locale) => void; theme: Theme; toggleTheme: () => void; t: Copy } | null>(null)

export function AppProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocale] = useState<Locale>('vi')
  const [theme, setTheme] = useState<Theme>('light')
  useEffect(() => { document.documentElement.lang = locale === 'vi' ? 'vi' : 'en'; document.documentElement.dataset.theme = theme }, [locale, theme])
  const value = useMemo(() => ({ locale, setLocale, theme, toggleTheme: () => setTheme((value) => value === 'light' ? 'dark' : 'light'), t: copy[locale] }), [locale, theme])
  return <AppContext.Provider value={value}>{children}</AppContext.Provider>
}

export function useApp() {
  const context = useContext(AppContext)
  if (!context) throw new Error('useApp must be used within AppProvider')
  return context
}

export type { Locale }
