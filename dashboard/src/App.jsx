import { useCallback, useEffect, useState } from 'react'
import { supabase } from './supabaseClient'
import { Monitor, AlertTriangle, CheckCircle, ServerCrash, X, FileSearch, ShieldAlert, Clock, Network, MapPin, Download, HelpCircle, Settings, Sparkles, Terminal, Send } from 'lucide-react'
import './index.css'

const AGENT_UPDATE_COMMAND = "$ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $dir = 'C:\\ProgramData\\Enlace360\\Agent'; $agent = Join-Path $dir 'Agente_Enlace360_Service.ps1'; $cache = Join-Path $dir 'agent_payload.cache'; New-Item -ItemType Directory -Path $dir -Force | Out-Null; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Enlace360/Monitoreo-de-red-/main/Agente_Enlace360_Service.ps1' -OutFile $agent -UseBasicParsing; [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($agent)) | Set-Content -Path $cache -Encoding ASCII -Force; Write-Output 'Descarga completada. Cache local actualizado.'"

const getIntegrityInfo = (kiosk = {}) => {
  const status = String(kiosk.integrity_status || 'unknown').toLowerCase()
  const alert = kiosk.integrity_alert || ''

  if (status === 'critical') {
    return { status: 'critical', label: 'Integridad crítica', title: alert || 'Faltan archivos o tareas críticas del agente.' }
  }
  if (status === 'warning') {
    return { status: 'warning', label: 'Integridad alerta', title: alert || 'Hay componentes de respaldo faltantes o detenidos.' }
  }
  if (status === 'ok') {
    return { status: 'ok', label: 'Integridad OK', title: alert || 'Integridad OK' }
  }

  return { status: 'unknown', label: 'Sin integridad', title: 'Este agente aún no reporta integrity_status.' }
}

function App() {
  const [allKiosks, setAllKiosks] = useState([])
  const [allEvents, setAllEvents] = useState([])

  const [clients, setClients] = useState([])
  const [selectedClient, setSelectedClient] = useState('Todos')

  const [loading, setLoading] = useState(true)
  const [selectedEvent, setSelectedEvent] = useState(null)
  const [showGlossary, setShowGlossary] = useState(false)

  // AI Copilot States
  const [showSettings, setShowSettings] = useState(false)
  const [apiKey, setApiKey] = useState(localStorage.getItem('enlace360_ai_key') || '')
  const [aiLoading, setAiLoading] = useState(false)
  const [aiResponse, setAiResponse] = useState(null)

  // Remote Commands (C2) States
  const [terminalKiosk, setTerminalKiosk] = useState(null)
  const [remoteCommands, setRemoteCommands] = useState([])
  const [commandInput, setCommandInput] = useState('')

  const saveApiKey = (key) => {
    setApiKey(key)
    localStorage.setItem('enlace360_ai_key', key)
  }

  const analyzeWithAI = async (event) => {
    setAiLoading(true)
    setAiResponse(null)

    const kioscosMismaSucursal = allKiosks.filter(k => k.location === event.location && k.kiosk_id !== event.kiosk_id)
    const estadoSucursal = kioscosMismaSucursal.length > 0
      ? kioscosMismaSucursal.map(k => `Kiosco ${k.kiosk_id}: ${k.status}`).join(', ')
      : 'No hay otros kioscos registrados en esta sucursal.'

    const prompt = `Eres el Arquitecto de Red Senior de Enlace 360.
Analiza la siguiente caída de red de un kiosco comercial.
Equipo Afectado: ${event.kiosk_id}
Cliente: ${event.client_name}
Sucursal: ${event.location || 'N/A'}
Causa Cruda: ${event.probable_cause}
Diagnóstico Técnico: ${JSON.stringify(event.diagnostics)}

Contexto de la Sucursal: ${estadoSucursal}

Explícale a un agente de soporte de Nivel 0 (sin conocimientos técnicos) qué significa esto y qué acciones inmediatas debe tomar. Sé muy breve (máximo 4 líneas) y directo. No saludes.`

    try {
      // Usando Pollinations.ai (Open, sin API Key) para ambiente de pruebas
      const res = await fetch('https://text.pollinations.ai/', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          messages: [{ role: 'user', content: prompt }]
        })
      })

      if (!res.ok) {
        throw new Error(`Error de conexión HTTP: ${res.status}`)
      }
      
      const textResponse = await res.text()
      setAiResponse(textResponse)
    } catch (err) {
      setAiResponse(`Error: ${err.message}`)
    } finally {
      setAiLoading(false)
    }
  }

  // C2 Functions
  const fetchRemoteCommands = useCallback(async (kioskId) => {
    const { data, error } = await supabase
      .from('remote_commands')
      .select('*')
      .eq('kiosk_id', kioskId)
      .order('created_at', { ascending: false })
      .limit(20)
    if (!error && data) setRemoteCommands(data)
  }, [])

  const sendCommand = async (cmdString) => {
    if (!cmdString.trim() || !terminalKiosk) return
    const { error } = await supabase
      .from('remote_commands')
      .insert([{ kiosk_id: terminalKiosk, command_string: cmdString, status: 'pending' }])
    if (!error) {
      setCommandInput('')
      fetchRemoteCommands(terminalKiosk)
    } else {
      alert("Error enviando comando: " + error.message)
    }
  }

  const updateAllAgents = async () => {
    const targetKiosks = filteredKiosks
    if (targetKiosks.length === 0) {
      alert('No hay kioscos visibles para actualizar.')
      return
    }
    if (!window.confirm(`¿Actualizar el agente en ${targetKiosks.length} kioscos? El cambio se aplicará automáticamente.`)) return
    let sent = 0
    for (const kiosk of targetKiosks) {
      const { error } = await supabase
        .from('remote_commands')
        .insert([{ kiosk_id: kiosk.kiosk_id, command_string: AGENT_UPDATE_COMMAND, status: 'pending' }])
      if (!error) sent++
    }
    alert(`Comando de actualización enviado a ${sent}/${targetKiosks.length} kioscos.`)
  }

  useEffect(() => {
    let interval
    let initialFetch
    if (terminalKiosk) {
      initialFetch = setTimeout(() => fetchRemoteCommands(terminalKiosk), 0)
      interval = setInterval(() => fetchRemoteCommands(terminalKiosk), 5000)
    }
    return () => {
      clearTimeout(initialFetch)
      clearInterval(interval)
    }
  }, [terminalKiosk, fetchRemoteCommands])

  const exportToCSV = () => {
    if (allEvents.length === 0) return;
    const headers = ['Kiosco', 'Cliente', 'Sucursal', 'Causa Probable', 'Fecha Caída', 'Fecha Recuperación', 'Estado'];
    const rows = allEvents.map(e => [
      e.kiosk_id,
      e.client_name,
      e.location || 'Sede Principal',
      e.probable_cause,
      new Date(e.offline_time).toLocaleString(),
      e.online_time ? new Date(e.online_time).toLocaleString() : 'Aún Caído',
      e.online_time ? 'Recuperado' : 'Crítico'
    ]);

    const csvContent = "data:text/csv;charset=utf-8,"
      + headers.join(",") + "\n"
      + rows.map(e => e.map(cell => `"${cell}"`).join(",")).join("\n");

    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", `Reporte_Red_Enlace360_${new Date().toLocaleDateString()}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  }

  const fetchData = useCallback(async () => {
    try {
      const { data: kiosksData } = await supabase
        .from('kiosks')
        .select('*')
        .order('kiosk_id', { ascending: true })

      const { data: eventsData } = await supabase
        .from('network_events')
        .select('*')
        .order('offline_time', { ascending: false })
        .limit(30)

      let rawKiosks = kiosksData || []
      let finalEvents = eventsData || []

      // Lógica de Heartbeat (Latido)
      // Si el equipo no ha reportado latido en más de 6 minutos, asumimos que está apagado
      let finalKiosks = rawKiosks.map(kiosk => {
        if (kiosk.status === 'online' && kiosk.last_heartbeat) {
          const lastHeartbeatTime = new Date(kiosk.last_heartbeat).getTime()
          const currentTime = new Date().getTime()
          const minutesSince = (currentTime - lastHeartbeatTime) / 60000

          if (minutesSince > 10) {
            return { ...kiosk, status: 'offline', uptime: 'Apagado o Sin Red' }
          }

          if (kiosk.latency_ms && kiosk.latency_ms > 500) {
            return { ...kiosk, status: 'degraded', uptime: `${kiosk.latency_ms}ms (Lento)` }
          }
        }
        return kiosk
      })

      if (finalKiosks.length === 0) {
        finalKiosks = []
        finalEvents = []

        const malls = ['Mall La Reina', 'Mall La Florida', 'Mall La Dehesa']

        malls.forEach((mall, mallIndex) => {
          // Generamos 10 equipos por sucursal
          for (let i = 1; i <= 10; i++) {
            // Decidimos cuáles están caídos (ej. el 3 siempre, y el 7 en algunos)
            const isOffline = (i === 3 || (i === 7 && mallIndex !== 2))
            const kioskPrefix = mall.replace('Mall La ', '').toUpperCase()
            const kioskId = `TOTEM-${kioskPrefix}-${i.toString().padStart(2, '0')}`

            finalKiosks.push({
              kiosk_id: kioskId,
              client_name: 'Cenco Malls',
              location: mall,
              status: isOffline ? 'offline' : 'online',
              uptime: isOffline ? 'Desconocido' : `${Math.floor(Math.random() * 14) + 1} días, ${Math.floor(Math.random() * 12)} horas`
            })

            if (isOffline) {
              const cause = i === 3 ? 'CABLE DESCONECTADO O PUERTO APAGADO (Falla de Capa 1)' : 'GATEWAY INACCESIBLE. Posible falla de switch/router.';
              finalEvents.push({
                id: Math.random().toString(),
                kiosk_id: kioskId,
                client_name: 'Cenco Malls',
                location: mall,
                // Fecha de caída aleatoria en las últimas horas
                offline_time: new Date(Date.now() - Math.random() * 86400000).toISOString(),
                probable_cause: cause,
                diagnostics: {
                  Timestamp: new Date().toISOString(),
                  Uptime: "14 días, 3 horas",
                  GatewayIP: "192.168.1.1",
                  GatewayReachable: i !== 3,
                  Adapters: [
                    { Name: "Ethernet", InterfaceDescription: "Intel Gigabit Network", Status: i === 3 ? "Disconnected" : "Up" }
                  ]
                }
              })
            }
          }
        })
      }

      setAllKiosks(finalKiosks)
      setAllEvents(finalEvents)

      const uniqueClients = [...new Set(finalKiosks.map(k => k.client_name))]
      setClients(uniqueClients)

      // Si solo hay un cliente, autoseleccionarlo en lugar de 'Todos' para mejor UX
      if (uniqueClients.length === 1 && selectedClient === 'Todos') {
        setSelectedClient(uniqueClients[0])
      }

    } catch (error) {
      console.error('Error fetching data:', error.message)
    } finally {
      setLoading(false)
    }
  }, [selectedClient])

  useEffect(() => {
    const initialFetch = setTimeout(fetchData, 0)

    const kioskSubscription = supabase
      .channel('kiosks-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'kiosks' }, () => {
        fetchData()
      })
      .subscribe()

    const intervalId = setInterval(() => {
      fetchData()
    }, 60000) // Refrescar cada 1 minuto para evaluar heartbeats

    return () => {
      clearTimeout(initialFetch)
      supabase.removeChannel(kioskSubscription)
      clearInterval(intervalId)
    }
  }, [fetchData])

  if (loading) {
    return (
      <div className="loading-container">
        <div className="spinner"></div>
        <p>Sincronizando con Kioscos...</p>
      </div>
    )
  }

  const filteredKiosks = selectedClient === 'Todos' ? allKiosks : allKiosks.filter(k => k.client_name === selectedClient)
  const filteredEvents = selectedClient === 'Todos' ? allEvents : allEvents.filter(e => e.client_name === selectedClient)

  const onlineCount = filteredKiosks.filter(k => k.status === 'online').length
  const offlineCount = filteredKiosks.filter(k => k.status === 'offline').length
  const integrityCount = filteredKiosks.filter(k => ['critical', 'warning'].includes(getIntegrityInfo(k).status)).length
  const totalCount = filteredKiosks.length

  // Agrupar los kioscos filtrados por Sucursal (location)
  const kiosksByLocation = filteredKiosks.reduce((acc, kiosk) => {
    const loc = kiosk.location || 'Sede Principal'
    if (!acc[loc]) acc[loc] = []
    acc[loc].push(kiosk)
    return acc
  }, {})

  return (
    <div className="dashboard-container">
      <header className="header">
        <div className="brand-container">
          <img src="/logo.png" alt="Enlace 360" className="brand-logo" onError={(e) => {
            e.target.style.display = 'none';
            e.target.nextSibling.style.display = 'block';
          }} />
          <h1 style={{ display: 'none', margin: 0, color: 'var(--brand-cyan)' }}>ENLACE 360</h1>

          <select
            className="client-selector"
            value={selectedClient}
            onChange={(e) => setSelectedClient(e.target.value)}
          >
            <option value="Todos">Todos los Clientes ({allKiosks.length})</option>
            {clients.map(c => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>
        </div>

        <div style={{ display: 'flex', gap: '15px', alignItems: 'center' }}>
          <button
            onClick={() => setShowSettings(true)}
            style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)', color: 'var(--text-muted)', padding: '8px', borderRadius: '50%', cursor: 'pointer', display: 'flex', transition: 'all 0.2s' }}
            title="Configuración IA"
            onMouseOver={(e) => { e.currentTarget.style.color = 'var(--brand-cyan)'; e.currentTarget.style.borderColor = 'var(--brand-cyan)' }}
            onMouseOut={(e) => { e.currentTarget.style.color = 'var(--text-muted)'; e.currentTarget.style.borderColor = 'rgba(255,255,255,0.1)' }}
          >
            <Settings size={20} />
          </button>
          <div className="header-status">
            <div className="live-dot"></div>
            Monitoreo Activo
          </div>
        </div>
      </header>

      <div className="stats-row">
        <div className="glass-panel stat-card">
          <div className="stat-icon"><Monitor size={28} color="var(--brand-cyan)" /></div>
          <div className="stat-info">
            <p>Total Equipos</p>
            <h3>{totalCount}</h3>
          </div>
        </div>
        <div className="glass-panel stat-card">
          <div className="stat-icon" style={{ borderColor: 'rgba(0,230,118,0.2)', boxShadow: 'inset 0 0 10px rgba(0,230,118,0.1)' }}>
            <CheckCircle size={28} color="var(--status-online)" />
          </div>
          <div className="stat-info">
            <p>Sanos (Online)</p>
            <h3 style={{ color: 'var(--status-online)' }}>{onlineCount}</h3>
          </div>
        </div>
        <div className="glass-panel stat-card">
          <div className="stat-icon" style={{ borderColor: 'rgba(255,23,68,0.2)', boxShadow: 'inset 0 0 10px rgba(255,23,68,0.1)' }}>
            <ServerCrash size={28} color="var(--status-offline)" />
          </div>
          <div className="stat-info">
            <p>Caídos (Offline)</p>
            <h3 style={{ color: 'var(--status-offline)' }}>{offlineCount}</h3>
          </div>
        </div>
        <div className="glass-panel stat-card">
          <div className="stat-icon" style={{ borderColor: 'rgba(255,145,0,0.25)', boxShadow: 'inset 0 0 10px rgba(255,145,0,0.1)' }}>
            <ShieldAlert size={28} color="var(--status-warning)" />
          </div>
          <div className="stat-info">
            <p>Integridad</p>
            <h3 style={{ color: integrityCount > 0 ? 'var(--status-warning)' : 'var(--status-online)' }}>{integrityCount}</h3>
          </div>
        </div>
      </div>

      <div className="dashboard-layout">
        <main className="glass-panel main-panel">
          <h2 className="panel-title"><Monitor size={22} color="var(--brand-cyan)" /> Flota de Kioscos
            <button
              onClick={updateAllAgents}
              style={{ marginLeft: 'auto', background: 'rgba(0,194,255,0.1)', border: '1px solid rgba(0,194,255,0.3)', color: 'var(--brand-cyan)', padding: '6px 14px', borderRadius: '8px', fontSize: '0.75rem', cursor: 'pointer', fontWeight: '600', transition: 'all 0.2s', display: 'flex', alignItems: 'center', gap: '6px' }}
              onMouseOver={(e) => { e.currentTarget.style.background = 'rgba(0,194,255,0.25)' }}
              onMouseOut={(e) => { e.currentTarget.style.background = 'rgba(0,194,255,0.1)' }}
              title="Enviar actualización de agente a todos los kioscos"
            >
              <Download size={14} /> Actualizar Todos
            </button>
          </h2>

          <div className="locations-container">
            {Object.entries(kiosksByLocation).map(([location, groupKiosks]) => (
              <div key={location} className="location-group">
                <h3 className="location-title">
                  <MapPin size={18} color="var(--brand-cyan)" />
                  {location}
                  <span className="location-count">({groupKiosks.length})</span>
                </h3>
                <div className="kiosk-grid">
                  {groupKiosks.map((kiosk, idx) => {
                    const integrity = getIntegrityInfo(kiosk)
                    return (
                      <div key={idx} className={`kiosk-card integrity-${integrity.status} ${kiosk.status}`} style={{ position: 'relative' }}>
                        <div className="status-indicator"></div>
                        {(() => {
                          const parts = (kiosk.uptime || '').split(' | ')
                          const version = parts.length > 1 ? parts[1] : null
                          return version ? (
                            <span style={{ position: 'absolute', top: '8px', right: '8px', background: 'rgba(0,194,255,0.15)', color: 'var(--brand-cyan)', fontSize: '0.6rem', padding: '2px 7px', borderRadius: '8px', fontWeight: '600', letterSpacing: '0.5px', border: '1px solid rgba(0,194,255,0.2)' }}>
                              {version}
                            </span>
                          ) : null
                        })()}
                        <div className="kiosk-name">{kiosk.kiosk_id}</div>
                        <div className="kiosk-uptime">{(kiosk.uptime || 'Iniciando...').split(' | ')[0]}</div>
                        {integrity.status !== 'ok' && (
                          <div className={`integrity-pill ${integrity.status}`} title={integrity.title}>
                            {integrity.label}
                          </div>
                        )}
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '8px', display: 'flex', flexDirection: 'column', gap: '2px', background: 'rgba(0,0,0,0.15)', padding: '5px', borderRadius: '4px' }}>
                          <span>IP: {kiosk.ip_address || 'Desconocida'}</span>
                          {kiosk.mac_address && <span>MAC: {kiosk.mac_address}</span>}
                        </div>
                        <button
                          className="terminal-btn"
                          onClick={(e) => { e.stopPropagation(); setTerminalKiosk(kiosk.kiosk_id) }}
                          style={{ position: 'absolute', bottom: '10px', right: '10px', background: 'transparent', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', opacity: 0.7, padding: '5px' }}
                          title="Abrir Terminal Remota"
                          onMouseOver={(e) => { e.currentTarget.style.color = 'var(--brand-cyan)'; e.currentTarget.style.opacity = 1 }}
                          onMouseOut={(e) => { e.currentTarget.style.color = 'var(--text-muted)'; e.currentTarget.style.opacity = 0.7 }}
                        >
                          <Terminal size={18} />
                        </button>
                      </div>
                    )
                  })}
                </div>
              </div>
            ))}
          </div>
        </main>

        <aside className="glass-panel">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h2 className="panel-title" style={{ margin: 0 }}><AlertTriangle size={22} color="var(--status-warning)" /> Últimas Caídas</h2>
            <div style={{ display: 'flex', gap: '8px' }}>
              <button
                onClick={() => setShowGlossary(true)}
                style={{ background: 'transparent', border: '1px solid var(--text-muted)', color: 'var(--text-muted)', padding: '5px 10px', borderRadius: '5px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '5px', fontSize: '0.8rem' }}
                title="Ver diccionario de fallas"
              >
                <HelpCircle size={14} /> Diccionario
              </button>
              <button
                onClick={exportToCSV}
                style={{ background: 'transparent', border: '1px solid var(--brand-cyan)', color: 'var(--brand-cyan)', padding: '5px 10px', borderRadius: '5px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '5px', fontSize: '0.8rem' }}
                title="Descargar Reporte CSV para SLA"
              >
                <Download size={14} /> Exportar CSV
              </button>
            </div>
          </div>
          <div className="events-list">
            {filteredEvents.length === 0 ? (
              <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem', textAlign: 'center', marginTop: '2rem' }}>
                No hay incidentes recientes.
              </p>
            ) : (
              filteredEvents.map((ev, idx) => (
                <div key={idx} className="event-item" onClick={() => setSelectedEvent(ev)}>
                  <div className="event-header">
                    <span className="event-kiosk"><ShieldAlert size={16} color="var(--status-offline)" /> {ev.kiosk_id}</span>
                    <span className="event-time">
                      {new Date(ev.offline_time).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                    </span>
                  </div>
                  <div className="event-location"><MapPin size={12} /> {ev.location || 'Sede Principal'}</div>
                  <p className="event-cause">{ev.probable_cause}</p>
                </div>
              ))
            )}
          </div>
        </aside>
      </div>

      {/* MODAL DE REPORTE (THE ALIBI) */}
      {selectedEvent && (
        <div className="modal-overlay" onClick={() => setSelectedEvent(null)}>
          <div className="modal-content" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h2><FileSearch size={26} /> Reporte de Incidente de Red</h2>
              <button className="close-btn" onClick={() => setSelectedEvent(null)}><X size={24} /></button>
            </div>
            <div className="modal-body">
              <div style={{ marginBottom: '2rem' }}>
                <p style={{ margin: '0 0 5px 0', color: 'var(--text-muted)' }}>Kiosco Afectado</p>
                <h3 style={{ margin: 0, fontSize: '1.8rem' }}>{selectedEvent.kiosk_id}</h3>
                <div style={{ display: 'flex', gap: '15px', marginTop: '8px' }}>
                  <span style={{ color: 'var(--brand-cyan)', display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <strong>Cliente:</strong> {selectedEvent.client_name}
                  </span>
                  <span style={{ color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <MapPin size={14} /> {selectedEvent.location || 'Sede Principal'}
                  </span>
                </div>
              </div>

              <div className="alibi-section" style={{ borderColor: 'rgba(255, 23, 68, 0.3)', background: 'rgba(255, 23, 68, 0.05)' }}>
                <h3 style={{ color: 'var(--status-offline)' }}><AlertTriangle size={20} /> Causa Raíz Probable</h3>
                <p style={{ fontSize: '1.1rem', fontWeight: '500', margin: 0 }}>{selectedEvent.probable_cause}</p>
              </div>

              <div className="alibi-section">
                <h3><Clock size={20} /> Tiempos del Evento</h3>
                <p><strong>Caída de red detectada:</strong> {new Date(selectedEvent.offline_time).toLocaleString()}</p>
                {selectedEvent.online_time && (
                  <p><strong>Red restablecida:</strong> {new Date(selectedEvent.online_time).toLocaleString()}</p>
                )}
                {selectedEvent.diagnostics?.Uptime && (
                  <p><strong>Uptime (Confirmación de no reinicio):</strong> {selectedEvent.diagnostics.Uptime}</p>
                )}
              </div>

              {selectedEvent.diagnostics && Object.keys(selectedEvent.diagnostics).length > 0 && (
                <div className="alibi-section">
                  <h3><Network size={20} /> Diagnóstico Forense de Red</h3>

                  {selectedEvent.diagnostics.Adapters && (
                    <div style={{ marginBottom: '1.5rem' }}>
                      <p style={{ color: 'var(--text-muted)', marginBottom: '10px' }}>Estado de Tarjetas de Red (Físico):</p>
                      {selectedEvent.diagnostics.Adapters.map((a, i) => (
                        <div key={i} style={{ background: 'rgba(0,0,0,0.3)', padding: '10px', borderRadius: '8px', marginBottom: '5px' }}>
                          <strong>{a.Name}:</strong> {a.InterfaceDescription}
                          <span className={`status-badge ${a.Status?.toLowerCase()}`} style={{ float: 'right' }}>
                            {a.Status}
                          </span>
                        </div>
                      ))}
                    </div>
                  )}

                  <div style={{ marginBottom: '1.5rem' }}>
                    <p style={{ color: 'var(--text-muted)', marginBottom: '10px' }}>Conectividad Local (Gateway):</p>
                    <div style={{ background: 'rgba(0,0,0,0.3)', padding: '10px', borderRadius: '8px' }}>
                      <strong>IP del Router Local:</strong> {selectedEvent.diagnostics.GatewayIP || 'No detectada'} <br />
                      <strong>Conexión con el Router:</strong> {selectedEvent.diagnostics.GatewayReachable ? '✅ Responde (El cable local está bien)' : '❌ No responde'}
                    </div>
                  </div>

                  <div>
                    <p style={{ color: 'var(--text-muted)', marginBottom: '10px' }}>Registro Completo del Sistema (Raw JSON):</p>
                    <div className="code-block">
                      <pre style={{ margin: 0 }}>
                        {JSON.stringify(selectedEvent.diagnostics, null, 2)}
                      </pre>
                    </div>
                  </div>
                </div>
              )}

              {/* IA COPILOT SECTION */}
              <div className="alibi-section" style={{ borderColor: 'rgba(0, 163, 218, 0.4)', background: 'linear-gradient(180deg, rgba(0, 163, 218, 0.05) 0%, rgba(0, 163, 218, 0) 100%)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '15px' }}>
                  <h3 style={{ color: 'var(--brand-cyan)', margin: 0 }}><Sparkles size={20} /> Copiloto IA de Soporte</h3>
                  {!aiLoading && !aiResponse && (
                    <button
                      onClick={() => analyzeWithAI(selectedEvent)}
                      style={{ background: 'var(--brand-cyan)', color: '#fff', border: 'none', padding: '8px 16px', borderRadius: '8px', fontWeight: '600', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px', boxShadow: '0 4px 12px var(--brand-cyan-glow)' }}
                    >
                      <Sparkles size={16} /> Analizar Incidente
                    </button>
                  )}
                </div>

                {aiLoading && (
                  <div style={{ padding: '20px', textAlign: 'center', color: 'var(--brand-cyan)' }}>
                    <div className="spinner" style={{ margin: '0 auto 10px auto', width: '24px', height: '24px', borderTopColor: 'var(--brand-cyan)' }}></div>
                    <p style={{ margin: 0, fontWeight: '500' }}>El Copiloto está analizando los logs...</p>
                  </div>
                )}

                {aiResponse && (
                  <div style={{ background: 'rgba(0,0,0,0.4)', padding: '15px', borderRadius: '8px', borderLeft: '4px solid var(--brand-cyan)' }}>
                    <p style={{ margin: 0, fontSize: '1rem', lineHeight: '1.6', whiteSpace: 'pre-wrap' }}>
                      {aiResponse}
                    </p>
                  </div>
                )}
              </div>

            </div>
          </div>
        </div>
      )}

      {/* MODAL DE GLOSARIO */}
      {showGlossary && (
        <div className="modal-overlay" onClick={() => setShowGlossary(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()} style={{ maxWidth: '700px' }}>
            <div className="modal-header">
              <h2><HelpCircle size={26} /> Glosario de Fallas (Causa Raíz)</h2>
              <button className="close-btn" onClick={() => setShowGlossary(false)}><X size={24} /></button>
            </div>
            <div className="modal-body">
              <p style={{ color: 'var(--text-muted)', marginBottom: '20px' }}>
                Este diccionario explica los diagnósticos forenses automáticos que realiza el Agente de Red y qué acciones debe tomar el equipo de soporte en cada caso.
              </p>

              <div className="alibi-section">
                <h3 style={{ color: 'var(--status-offline)', display: 'flex', alignItems: 'center', gap: '8px', margin: '0 0 10px 0' }}>🔌 CABLE DESCONECTADO O PUERTO APAGADO (Capa 1)</h3>
                <p style={{ margin: '0 0 5px 0' }}><strong>Qué significa:</strong> El kiosco detectó que el cable de red físico fue desconectado, dañado, o que el switch al que está conectado se quedó sin energía.</p>
                <p style={{ margin: 0 }}><strong>Qué hacer:</strong> Pedir al personal en tienda que revise físicamente el cable de red detrás del kiosco y confirme que el router esté encendido.</p>
              </div>

              <div className="alibi-section">
                <h3 style={{ color: 'var(--status-offline)', display: 'flex', alignItems: 'center', gap: '8px', margin: '0 0 10px 0' }}>⚠️ SIN GATEWAY / SIN DHCP. El equipo no obtuvo IP.</h3>
                <p style={{ margin: '0 0 5px 0' }}><strong>Qué significa:</strong> El cable está conectado, pero el router local no le asignó una dirección IP al kiosco (Falla del servidor DHCP).</p>
                <p style={{ margin: 0 }}><strong>Qué hacer:</strong> Reiniciar el router del local. Si persiste, TI debe revisar la configuración de red local.</p>
              </div>

              <div className="alibi-section">
                <h3 style={{ color: 'var(--status-warning)', display: 'flex', alignItems: 'center', gap: '8px', margin: '0 0 10px 0' }}>🚧 GATEWAY INACCESIBLE. Posible falla de switch/router.</h3>
                <p style={{ margin: '0 0 5px 0' }}><strong>Qué significa:</strong> El kiosco tiene IP asignada y el cable está bien, pero no puede comunicarse con la puerta de enlace (router). Probablemente el router está bloqueado o un switch intermedio está colgado.</p>
                <p style={{ margin: 0 }}><strong>Qué hacer:</strong> Reiniciar switches y router de la sucursal.</p>
              </div>

              <div className="alibi-section">
                <h3 style={{ color: 'var(--brand-cyan)', display: 'flex', alignItems: 'center', gap: '8px', margin: '0 0 10px 0' }}>🌐 SIN SALIDA A INTERNET. El ISP del cliente está caído.</h3>
                <p style={{ margin: '0 0 5px 0' }}><strong>Qué significa:</strong> La red interna de la tienda está perfecta (el cable y el router responden impecable), pero el proveedor de internet (Movistar, Claro, VTR) se cayó a nivel calle.</p>
                <p style={{ margin: 0 }}><strong>Qué hacer:</strong> Levantar ticket urgente con el proveedor ISP. La falla es de ellos.</p>
              </div>

              <div className="alibi-section">
                <h3 style={{ color: 'var(--brand-cyan)', display: 'flex', alignItems: 'center', gap: '8px', margin: '0 0 10px 0' }}>🔍 FALLA DE DNS.</h3>
                <p style={{ margin: '0 0 5px 0' }}><strong>Qué significa:</strong> Hay internet, pero el "traductor" de páginas (Servidor DNS) no responde.</p>
                <p style={{ margin: 0 }}><strong>Qué hacer:</strong> Cambiar los DNS del equipo a 8.8.8.8 o contactar al ISP.</p>
              </div>

              <div className="alibi-section" style={{ borderColor: 'rgba(0, 230, 118, 0.3)', background: 'rgba(0, 230, 118, 0.05)' }}>
                <h3 style={{ color: 'var(--status-online)', display: 'flex', alignItems: 'center', gap: '8px', margin: '0 0 10px 0' }}>✅ AUTO-REPARADO (Micro-corte)</h3>
                <p style={{ margin: '0 0 5px 0' }}><strong>Qué significa:</strong> Hubo una pérdida temporal de paquetes (muy común en Wi-Fi o ruido eléctrico), pero el Agente aplicó un reinicio interno de las tarjetas y revivió la conexión en milisegundos.</p>
                <p style={{ margin: 0 }}><strong>Qué hacer:</strong> ¡Nada! Es solo evidencia de que el Agente está trabajando y salvó el día.</p>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* MODAL DE TERMINAL C2 */}
      {terminalKiosk && (
        <div className="modal-overlay" onClick={() => setTerminalKiosk(null)}>
          <div className="modal-content terminal-modal" onClick={e => e.stopPropagation()} style={{ maxWidth: '800px', width: '90%', background: '#0a0a0a' }}>
            <div className="modal-header" style={{ borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '15px' }}>
              <h2 style={{ display: 'flex', alignItems: 'center', gap: '10px', color: 'var(--brand-cyan)', margin: 0 }}>
                <Terminal size={24} /> 
                Terminal Remota: {terminalKiosk}
              </h2>
              <button className="close-btn" onClick={() => setTerminalKiosk(null)}><X size={24} /></button>
            </div>
            
            <div className="modal-body" style={{ padding: '20px 0 0 0' }}>
              <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap', marginBottom: '20px' }}>
                <button className="quick-cmd-btn" onClick={() => sendCommand('ipconfig /flushdns')}>Limpiar DNS</button>
                <button className="quick-cmd-btn" onClick={() => sendCommand('Get-NetAdapter -Physical | Restart-NetAdapter')}>Reiniciar Red</button>
                <button className="quick-cmd-btn" onClick={() => sendCommand(AGENT_UPDATE_COMMAND)}>Actualizar Agente</button>
                <button className="quick-cmd-btn danger" onClick={() => { if(window.confirm('¿Forzar reinicio del kiosco?')) sendCommand('Restart-Computer -Force') }}>Reiniciar PC</button>
              </div>

              <div className="terminal-logs">
                {remoteCommands.length === 0 ? (
                  <div style={{ color: 'rgba(255,255,255,0.3)', textAlign: 'center', marginTop: '40px' }}>No hay comandos recientes. Escribe un comando para empezar.</div>
                ) : (
                  remoteCommands.map(cmd => (
                    <div key={cmd.id} className="terminal-entry">
                      <div className="cmd-prompt"><span style={{color:'var(--brand-cyan)'}}>root@{terminalKiosk}:~#</span> {cmd.command_string}</div>
                      <div className="cmd-meta">Estado: <span className={`status-badge ${cmd.status}`}>{cmd.status.toUpperCase()}</span> | Enviado: {new Date(cmd.created_at).toLocaleTimeString()}</div>
                      {cmd.output_log && (
                        <pre className="cmd-output">{cmd.output_log}</pre>
                      )}
                    </div>
                  ))
                )}
              </div>

              <div className="terminal-input-container">
                <span style={{ color: 'var(--brand-cyan)', fontWeight: 'bold' }}>$</span>
                <input 
                  type="text" 
                  className="terminal-input"
                  value={commandInput}
                  onChange={(e) => setCommandInput(e.target.value)}
                  onKeyDown={(e) => { if(e.key === 'Enter') sendCommand(commandInput) }}
                  placeholder="Escribe un comando PowerShell..."
                  autoFocus
                />
                <button onClick={() => sendCommand(commandInput)} className="terminal-send-btn">
                  <Send size={18} />
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* MODAL DE AJUSTES IA */}
      {showSettings && (
        <div className="modal-overlay" onClick={() => setShowSettings(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()} style={{ maxWidth: '500px' }}>
            <div className="modal-header">
              <h2><Settings size={26} /> Configuración</h2>
              <button className="close-btn" onClick={() => setShowSettings(false)}><X size={24} /></button>
            </div>
            <div className="modal-body">
              <p style={{ color: 'var(--text-muted)', marginBottom: '20px', lineHeight: '1.5' }}>
                El <strong>Copiloto IA</strong> actualmente está funcionando en modo de pruebas mediante una API gratuita y abierta (Pollinations). No necesitas ninguna llave por ahora.
              </p>

              <div style={{ marginBottom: '20px', opacity: 0.5, pointerEvents: 'none' }}>
                <label style={{ display: 'block', marginBottom: '8px', fontWeight: '500', color: 'var(--brand-cyan)' }}>Google Gemini API Key</label>
                <input
                  type="password"
                  value={apiKey}
                  onChange={(e) => saveApiKey(e.target.value)}
                  placeholder="No requerida en fase de pruebas"
                  style={{ width: '100%', background: 'rgba(0,0,0,0.3)', border: '1px solid rgba(255,255,255,0.1)', color: 'white', padding: '12px', borderRadius: '8px', outline: 'none', fontFamily: 'monospace' }}
                />
              </div>

              <button
                onClick={() => setShowSettings(false)}
                style={{ width: '100%', background: 'var(--brand-cyan)', color: 'white', border: 'none', padding: '12px', borderRadius: '8px', fontWeight: '600', cursor: 'pointer' }}
              >
                Guardar y Cerrar
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  )
}

export default App
