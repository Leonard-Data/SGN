import { AuthForm } from '@/components/auth-form'
import { AuthShell } from '@/components/auth-shell'

export default function SignInPage() { return <AuthShell title="Welcome back" description="Enter your credentials to access your account."><AuthForm mode="sign-in" /></AuthShell> }
