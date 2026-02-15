import { useState, useEffect } from 'react'
import { listUsers, updatePlan, updateStatus } from './api'
import { useAuth } from './auth'

const PLANS = ['none', 'sms']
const STATUSES = ['active', 'inactive']

function PlanBadge({ plan }) {
  const colors = {
    none: 'bg-gray-100 text-gray-600',
    sms: 'bg-blue-100 text-blue-700',
  }
  return (
    <span className={`px-2 py-0.5 rounded text-xs font-medium ${colors[plan] || colors.none}`}>
      {plan}
    </span>
  )
}

function StatusBadge({ status }) {
  return (
    <span className={`px-2 py-0.5 rounded text-xs font-medium ${
      status === 'active' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
    }`}>
      {status}
    </span>
  )
}

function UserRow({ user, onUpdate }) {
  const [plan, setPlan] = useState(user.plan)
  const [saving, setSaving] = useState(false)

  const handlePlanChange = async (newPlan) => {
    setPlan(newPlan)
    setSaving(true)
    try {
      await updatePlan(user.id, newPlan)
      onUpdate()
    } catch (e) {
      alert('Failed to update plan: ' + e.message)
      setPlan(user.plan)
    } finally {
      setSaving(false)
    }
  }

  const handleStatusToggle = async () => {
    const newStatus = user.status === 'active' ? 'inactive' : 'active'
    setSaving(true)
    try {
      await updateStatus(user.id, newStatus)
      onUpdate()
    } catch (e) {
      alert('Failed to update status: ' + e.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <tr className={`border-b border-gray-100 hover:bg-gray-50 ${saving ? 'opacity-50' : ''}`}>
      <td className="px-4 py-3 text-sm text-gray-500">{user.id}</td>
      <td className="px-4 py-3 text-sm font-mono">{user.phone}</td>
      <td className="px-4 py-3 text-sm">{user.name || '-'}</td>
      <td className="px-4 py-3 text-sm">{user.business_name || '-'}</td>
      <td className="px-4 py-3 text-sm">{user.city || '-'}</td>
      <td className="px-4 py-3">
        <select
          value={plan}
          onChange={(e) => handlePlanChange(e.target.value)}
          disabled={saving}
          className="text-sm border border-gray-300 rounded px-2 py-1 bg-white"
        >
          {PLANS.map(p => <option key={p} value={p}>{p}</option>)}
        </select>
      </td>
      <td className="px-4 py-3 text-sm text-gray-500">
        {user.plan === 'none'
          ? '-'
          : user.plan_expires_at && new Date(user.plan_expires_at).getFullYear() >= 2099
            ? 'Lifetime'
            : user.plan_expires_at
              ? new Date(user.plan_expires_at).toLocaleDateString()
              : '-'}
      </td>
      <td className="px-4 py-3">
        <button
          onClick={handleStatusToggle}
          disabled={saving}
          className="cursor-pointer"
        >
          <StatusBadge status={user.status} />
        </button>
      </td>
      <td className="px-4 py-3 text-sm text-gray-500">
        {new Date(user.created_at).toLocaleDateString()}
      </td>
    </tr>
  )
}

export default function Dashboard() {
  const { logout } = useAuth()
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [search, setSearch] = useState('')

  const fetchUsers = async () => {
    try {
      setError(null)
      const data = await listUsers()
      setUsers(data || [])
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchUsers() }, [])

  const filtered = users.filter(u => {
    if (!search) return true
    const q = search.toLowerCase()
    return (
      u.phone?.toLowerCase().includes(q) ||
      u.name?.toLowerCase().includes(q) ||
      u.business_name?.toLowerCase().includes(q)
    )
  })

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto px-4 py-6">
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold text-gray-900">CallFlow Admin</h1>
          <div className="flex gap-2">
            <button
              onClick={() => { setLoading(true); fetchUsers() }}
              className="px-3 py-1.5 bg-gray-900 text-white text-sm rounded hover:bg-gray-700"
            >
              Refresh
            </button>
            <button
              onClick={logout}
              className="px-3 py-1.5 border border-gray-300 text-gray-700 text-sm rounded hover:bg-gray-100"
            >
              Logout
            </button>
          </div>
        </div>

        <div className="mb-4">
          <input
            type="text"
            placeholder="Search by phone, name, or business..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full max-w-md px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-gray-900"
          />
        </div>

        {error && (
          <div className="mb-4 p-3 bg-red-50 text-red-700 rounded-lg text-sm">
            {error}
          </div>
        )}

        {loading ? (
          <div className="text-center py-12 text-gray-500">Loading...</div>
        ) : (
          <div className="bg-white rounded-lg shadow overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-gray-200 bg-gray-50">
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">ID</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Phone</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Name</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Business</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">City</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Plan</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Expiry</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Created</th>
                </tr>
              </thead>
              <tbody>
                {filtered.length === 0 ? (
                  <tr>
                    <td colSpan="8" className="px-4 py-8 text-center text-gray-500 text-sm">
                      No users found
                    </td>
                  </tr>
                ) : (
                  filtered.map(u => (
                    <UserRow key={u.id} user={u} onUpdate={fetchUsers} />
                  ))
                )}
              </tbody>
            </table>
            <div className="px-4 py-2 border-t border-gray-100 text-xs text-gray-400">
              {filtered.length} of {users.length} users
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
