import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const FIREBASE_SERVICE_ACCOUNT = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!

interface ServiceAccount {
  project_id: string
  client_email: string
  private_key: string
}

async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }

  const header = { alg: 'RS256', typ: 'JWT' }
  const encode = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')

  const signingInput = `${encode(header)}.${encode(payload)}`

  // Import private key (PKCS8)
  const pemBody = sa.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '')
  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput),
  )

  const jwt = `${signingInput}.${btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')}`

  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const tokenData = await tokenRes.json()
  return tokenData.access_token
}

const TYPE_LABELS: Record<string, string> = {
  oilChange: 'Cambio de aceite',
  brakes: 'Frenos',
  engine: 'Motor',
  transmission: 'Transmisión',
  electrical: 'Sistema eléctrico',
  steering: 'Dirección',
  other: 'Mantenimiento general',
}

function buildMessage(alert: Record<string, unknown>): { title: string; body: string } {
  const rawType = alert.type as string
  const type = TYPE_LABELS[rawType] ?? rawType
  const description = alert.description as string
  const kmRemaining = alert.km_remaining as number | null
  const daysRemaining = alert.days_remaining as number | null

  if (kmRemaining !== null && kmRemaining <= 0) {
    return {
      title: '⚠️ Mantenimiento vencido',
      body: `${type} superó el límite por ${Math.abs(kmRemaining)} km — ${description}`,
    }
  }
  if (kmRemaining !== null) {
    return {
      title: '🔧 Mantenimiento próximo',
      body: `${type} en ${kmRemaining} km — ${description}`,
    }
  }
  if (daysRemaining !== null && daysRemaining <= 0) {
    return {
      title: '⚠️ Mantenimiento vencido',
      body: `${type} venció hace ${Math.abs(daysRemaining)} días — ${description}`,
    }
  }
  return {
    title: '🔧 Mantenimiento próximo',
    body: `${type} vence en ${daysRemaining} días — ${description}`,
  }
}

Deno.serve(async (_req) => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
  const sa: ServiceAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT)

  const { data: alerts, error } = await supabase.rpc('get_maintenance_alerts')
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }

  if (!alerts || alerts.length === 0) {
    return new Response(JSON.stringify({ sent: 0, message: 'No alerts' }))
  }

  const accessToken = await getFcmAccessToken(sa)
  const results = []

  for (const alert of alerts) {
    const { title, body } = buildMessage(alert)

    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: alert.fcm_token,
            notification: { title, body },
            data: {
              maintenance_id: String(alert.maintenance_id),
              type: 'maintenance_alert',
            },
            android: {
              priority: 'high',
              notification: { channel_id: 'maintenance_alerts' },
            },
          },
        }),
      },
    )

    results.push({ user_id: alert.user_id, fcm_status: res.status })
  }

  return new Response(JSON.stringify({ sent: results.length, results }))
})
