import { useEffect, useState } from 'react'
import { supabase } from './supabaseClient'
import { Monitor, AlertTriangle, CheckCircle, Activity, ServerCrash, X, FileSearch, ShieldAlert, Clock, Network, MapPin, Download, HelpCircle, Settings, Sparkles } from 'lucide-react'
import './index.css'

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

  const saveApiKey = (key) => {
    setApiKey(key)
    localStorage.setItem('enlace360_ai_key', key)
  }

  const analyzeWithAI = async (event) => {
    if (!apiKey) {
      alert('Primero debes configurar tu Llave de Google Gemini en los Ajustes.')
      setShowSettings(true)
      return
    }

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
      const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          contents: [{
            parts: [{ text: prompt }]
          }],
          generationConfig: {
            temperature: 0.3
          }
        })
      })

      if (!res.ok) {
        const errData = await res.json()
        throw new Error(`Gemini dice: ${errData.error?.message || res.statusText}`)
      }
      
      const data = await res.json()
      setAiResponse(data.candidates[0].content.parts[0].text)
    } catch (err) {
      setAiResponse(`Error: ${err.message}`)
    } finally {
      setAiLoading(false)
    }
  }

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

  useEffect(() => {
    fetchData()

    const kioskSubscription = supabase
      .channel('kiosks-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'kiosks' }, payload => {
        fetchData()
      })
      .subscribe()

    const intervalId = setInterval(() => {
      fetchData()
    }, 60000) // Refrescar cada 1 minuto para evaluar heartbeats

    return () => {
      supabase.removeChannel(kioskSubscription)
      clearInterval(intervalId)
    }
  }, [])

  const fetchData = async () => {
    try {
      const { data: kiosksData, error: kiosksError } = await supabase
        .from('kiosks')
        .select('*')
        .order('kiosk_id', { ascending: true })

      const { data: eventsData, error: eventsError } = await supabase
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

          if (minutesSince > 6) {
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
  }

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
      </div>

      <div className="dashboard-layout">
        <main className="glass-panel main-panel">
          <h2 className="panel-title"><Monitor size={22} color="var(--brand-cyan)" /> Flota de Kioscos</h2>

          <div className="locations-container">
            {Object.entries(kiosksByLocation).map(([location, groupKiosks]) => (
              <div key={location} className="location-group">
                <h3 className="location-title">
                  <MapPin size={18} color="var(--brand-cyan)" />
                  {location}
                  <span className="location-count">({groupKiosks.length})</span>
                </h3>
                <div className="kiosk-grid">
                  {groupKiosks.map((kiosk, idx) => (
                    <div key={idx} className={`kiosk-card ${kiosk.status}`}>
                      <div className="status-indicator"></div>
                      <div className="kiosk-name">{kiosk.kiosk_id}</div>
                      <div className="kiosk-uptime">{kiosk.uptime || 'Iniciando...'}</div>
                      <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '8px', display: 'flex', flexDirection: 'column', gap: '2px', background: 'rgba(0,0,0,0.15)', padding: '5px', borderRadius: '4px' }}>
                        <span>IP: {kiosk.ip_address || 'Desconocida'}</span>
                        {kiosk.mac_address && <span>MAC: {kiosk.mac_address}</span>}
                      </div>
                    </div>
                  ))}
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
                Para habilitar el <strong>Copiloto IA</strong>, ingresa tu llave de la API de Google Gemini (es 100% gratuita). Esta llave se guardará exclusivamente en tu navegador de forma segura.
              </p>

              <div style={{ marginBottom: '20px' }}>
                <label style={{ display: 'block', marginBottom: '8px', fontWeight: '500', color: 'var(--brand-cyan)' }}>Google Gemini API Key</label>
                <input
                  type="password"
                  value={apiKey}
                  onChange={(e) => saveApiKey(e.target.value)}
                  placeholder="AIzaSyBxxxxxxxxxxxxxxxxxxxxxxxx"
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
