import assert from 'node:assert/strict'

import {
  buildLatestRecoveryByKiosk,
  formatOnlineDuration,
  getAgentVersionFromUptime,
  getOnlineSince
} from '../dashboard/src/kioskTime.js'

const fixedNow = new Date('2026-05-11T00:50:37Z')

assert.equal(
  formatOnlineDuration('2026-05-11T00:36:00Z', fixedNow),
  'Online 14 min',
  'online counter should use dashboard online session time, not Windows uptime'
)

assert.equal(
  formatOnlineDuration('2026-05-11T00:50:10Z', fixedNow),
  'Online <1 min',
  'online counter should handle just-started sessions'
)

assert.equal(
  formatOnlineDuration('2026-05-10T22:05:00Z', fixedNow),
  'Online 2 h 45 min',
  'online counter should include hours and remaining minutes'
)

assert.equal(
  getAgentVersionFromUptime('0 d, 1 h, 45 m | v3.8.1'),
  'v3.8.1',
  'agent version should still be parsed from the legacy uptime field'
)

const latestRecoveryByKiosk = buildLatestRecoveryByKiosk([
  {
    kiosk_id: 'A',
    online_time: '2026-05-11T00:30:00Z',
    probable_cause: 'GATEWAY INACCESIBLE'
  },
  {
    kiosk_id: 'A',
    online_time: '2026-05-11T00:45:00Z',
    probable_cause: 'INTEGRIDAD AGENTE WARNING'
  },
  {
    kiosk_id: 'B',
    online_time: '2026-05-11T00:40:00Z',
    probable_cause: 'AUTO-REPARADO (Micro-corte)'
  }
])

assert.equal(
  getOnlineSince({ kiosk_id: 'A', created_at: '2026-05-11T00:10:00Z' }, latestRecoveryByKiosk),
  '2026-05-11T00:30:00.000Z',
  'integrity events should not reset the online duration'
)

assert.equal(
  getOnlineSince({ kiosk_id: 'B', created_at: '2026-05-11T00:10:00Z' }, latestRecoveryByKiosk),
  '2026-05-11T00:40:00.000Z',
  'network recoveries should reset the online duration'
)

assert.equal(
  getOnlineSince({ kiosk_id: 'C', created_at: '2026-05-11T00:36:00Z' }, latestRecoveryByKiosk),
  '2026-05-11T00:36:00.000Z',
  'new kiosks without recovery events should count from registration'
)

console.log('Dashboard kiosk time checks passed.')
