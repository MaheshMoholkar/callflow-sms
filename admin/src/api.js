const API_BASE = 'https://callflow-api-production.up.railway.app/api/v1'

async function request(path, options = {}) {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  const data = await res.json()
  if (!data.success) {
    throw new Error(data.error?.message || 'Request failed')
  }
  return data.data
}

export function listUsers() {
  return request('/admin/users')
}

export function updatePlan(id, plan) {
  return request(`/admin/users/${id}/plan`, {
    method: 'PUT',
    body: JSON.stringify({ plan }),
  })
}

export function updateStatus(id, status) {
  return request(`/admin/users/${id}/status`, {
    method: 'PUT',
    body: JSON.stringify({ status }),
  })
}
