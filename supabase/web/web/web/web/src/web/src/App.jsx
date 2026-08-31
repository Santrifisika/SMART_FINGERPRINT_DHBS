import React, { useState, useEffect } from 'react';
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';
const supabase = createClient(supabaseUrl, supabaseAnonKey);

export default function App() {
  const [session, setSession] = useState(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [attendance, setAttendance] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      if (session) fetchAttendance();
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
      if (session) fetchAttendance();
    });

    return () => subscription.unsubscribe();
  }, []);

  // Realtime subscription untuk absensi instan <= 200ms
  useEffect(() => {
    if (!session) return;

    const channel = supabase
      .channel('realtime-attendance')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'attendance' }, (payload) => {
        setAttendance((prev) => [payload.new, ...prev]);
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [session]);

  const fetchAttendance = async () => {
    const { data, error } = await supabase
      .from('attendance')
      .select('*, students(name, nis)')
      .order('timestamp', { ascending: false })
      .limit(20);
    
    if (!error && data) setAttendance(data);
  };

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) setError(error.message);
    setLoading(false);
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
  };

  if (!session) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100">
        <div className="bg-white p-8 rounded-xl shadow-md w-full max-w-md">
          <h2 className="text-2xl font-bold mb-6 text-center text-gray-800">Login Dashboard Absensi</h2>
          {error && <div className="bg-red-100 text-red-700 p-3 rounded mb-4 text-sm">{error}</div>}
          <form onSubmit={handleLogin} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
              <input 
                type="email" 
                value={email} 
                onChange={(e) => setEmail(e.target.value)} 
                required 
                className="w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="admin@sekolah.sch.id"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Password</label>
              <input 
                type="password" 
                value={password} 
                onChange={(e) => setPassword(e.target.value)} 
                required 
                className="w-full px-3 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="••••••••"
              />
            </div>
            <button 
              type="submit" 
              disabled={loading}
              className="w-full bg-blue-600 text-white py-2 rounded-lg font-semibold hover:bg-blue-700 transition"
            >
              {loading ? 'Memuat...' : 'Masuk Dashboard'}
            </button>
          </form>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50 p-6">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6 bg-white p-4 rounded-xl shadow-sm">
          <div>
            <h1 className="text-xl font-bold text-gray-800">Live Absensi Perangkat Fisik</h1>
            <p className="text-sm text-gray-500">Terhubung secara Realtime ($\le 200\,\text{ms}$)</p>
          </div>
          <button 
            onClick={handleLogout}
            className="bg-red-500 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-red-600 transition"
          >
            Keluar
          </button>
        </div>

        <div className="bg-white rounded-xl shadow-sm overflow-hidden">
          <div className="p-4 border-b font-semibold text-gray-700">Riwayat Kehadiran Terbaru</div>
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-gray-50 text-gray-600 text-sm border-b">
                  <th className="p-3">Waktu</th>
                  <th className="p-3">Nama Siswa</th>
                  <th className="p-3">Status</th>
                  <th className="p-3">Perangkat ID</th>
                </tr>
              </thead>
              <tbody className="divide-y text-sm">
                {attendance.length === 0 ? (
                  <tr>
                    <td colSpan="4" className="p-4 text-center text-gray-400">Belum ada data absensi masuk.</td>
                  </tr>
                ) : (
                  attendance.map((row, idx) => (
                    <tr key={idx} className="hover:bg-gray-50">
                      <td className="p-3">{new Date(row.timestamp).toLocaleTimeString()}</td>
                      <td className="p-3 font-medium">{row.students?.name || 'Siswa (ID: ' + row.student_id + ')'}</td>
                      <td className="p-3">
                        <span className="px-2 py-1 rounded text-xs bg-green-100 text-green-800 font-semibold">
                          {row.status || 'Hadir'}
                        </span>
                      </td>
                      <td className="p-3 text-gray-500">{row.device_id}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}
