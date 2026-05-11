const UPTIME_VERSION_SEPARATOR = ' | '

const getTimeMs = (value) => {
  if (!value) return null
  const time = value instanceof Date ? value.getTime() : new Date(value).getTime()
  return Number.isNaN(time) ? null : time
}

const toIso = (value) => {
  const time = getTimeMs(value)
  return time === null ? null : new Date(time).toISOString()
}

export const splitUptimeVersion = (uptime = '') => {
  const [systemUptime = '', ...versionParts] = String(uptime || '').split(UPTIME_VERSION_SEPARATOR)
  return {
    systemUptime: systemUptime.trim(),
    agentVersion: versionParts.join(UPTIME_VERSION_SEPARATOR).trim()
  }
}

export const getAgentVersionFromUptime = (uptime = '') => splitUptimeVersion(uptime).agentVersion

export const getAgentVersion = (kiosk = {}) => kiosk.agent_version || getAgentVersionFromUptime(kiosk.uptime)

export const getHeartbeatAgeMinutes = (lastHeartbeat, now = new Date()) => {
  const timestamp = getTimeMs(lastHeartbeat)
  const nowTimestamp = getTimeMs(now)
  if (timestamp === null || nowTimestamp === null) return null
  return Math.max(0, (nowTimestamp - timestamp) / 60000)
}

export const formatHeartbeatAge = (minutes) => {
  if (minutes === null) return 'Sin heartbeat'
  if (minutes < 1) return 'Hace menos de 1 min'
  if (minutes < 60) return `Hace ${Math.floor(minutes)} min`

  const totalMinutes = Math.floor(minutes)
  const hours = Math.floor(totalMinutes / 60)
  const remainingMinutes = totalMinutes % 60
  if (hours < 24) {
    return remainingMinutes > 0 ? `Hace ${hours} h ${remainingMinutes} min` : `Hace ${hours} h`
  }

  const days = Math.floor(hours / 24)
  const remainingHours = hours % 24
  return remainingHours > 0 ? `Hace ${days} d ${remainingHours} h` : `Hace ${days} d`
}

export const buildLatestRecoveryByKiosk = (events = []) => {
  const latestRecoveryByKiosk = new Map()

  for (const event of events || []) {
    const kioskId = event?.kiosk_id
    const onlineTime = getTimeMs(event?.online_time)
    const cause = String(event?.probable_cause || '').toUpperCase()

    if (!kioskId || onlineTime === null || cause.includes('INTEGRIDAD AGENTE')) continue

    const current = latestRecoveryByKiosk.get(kioskId)
    if (!current || onlineTime > current.timeMs) {
      latestRecoveryByKiosk.set(kioskId, {
        timeMs: onlineTime,
        iso: new Date(onlineTime).toISOString()
      })
    }
  }

  return latestRecoveryByKiosk
}

export const getOnlineSince = (kiosk = {}, latestRecoveryByKiosk = new Map()) => {
  const recovery = latestRecoveryByKiosk.get(kiosk.kiosk_id)
  const createdAt = getTimeMs(kiosk.created_at)

  if (recovery && (createdAt === null || recovery.timeMs >= createdAt)) {
    return recovery.iso
  }

  return toIso(kiosk.created_at)
}

export const formatOnlineDuration = (onlineSince, now = new Date()) => {
  const sinceTime = getTimeMs(onlineSince)
  const nowTime = getTimeMs(now)
  if (sinceTime === null || nowTime === null) return 'Online sin inicio'

  const totalMinutes = Math.max(0, Math.floor((nowTime - sinceTime) / 60000))
  if (totalMinutes < 1) return 'Online <1 min'
  if (totalMinutes < 60) return `Online ${totalMinutes} min`

  const hours = Math.floor(totalMinutes / 60)
  const remainingMinutes = totalMinutes % 60
  if (hours < 24) {
    return remainingMinutes > 0 ? `Online ${hours} h ${remainingMinutes} min` : `Online ${hours} h`
  }

  const days = Math.floor(hours / 24)
  const remainingHours = hours % 24
  return remainingHours > 0 ? `Online ${days} d ${remainingHours} h` : `Online ${days} d`
}
