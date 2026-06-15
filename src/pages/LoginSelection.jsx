import React from 'react';
import { useNavigate } from 'react-router-dom';

export default function LoginSelection() {
  const navigate = useNavigate();

  return (
    <div style={{
      minHeight: '100vh',
      background: '#ffffff',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '20px'
    }}>
      <div style={{
        background: '#fff',
        borderRadius: '20px',
        padding: '40px',
        boxShadow: '0 20px 40px rgba(0,0,0,0.1)',
        textAlign: 'center',
        maxWidth: '500px',
        width: '100%'
      }}>
        <div style={{
          background: '#ff8a00',
          width: '80px',
          height: '80px',
          borderRadius: '50%',
          margin: '0 auto 20px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: '32px'
        }}>
          🚗
        </div>
        
        <h1 style={{
          color: '#333',
          marginBottom: '10px',
          fontSize: '28px',
          fontWeight: '700'
        }}>
          IntelliClaims
        </h1>
        
        <p style={{
          color: '#666',
          marginBottom: '40px',
          fontSize: '16px'
        }}>
          Choose your login type to continue
        </p>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <button
            onClick={() => navigate('/admin-login')}
            style={{
              background: '#ff8a00',
              color: '#fff',
              border: 'none',
              borderRadius: '12px',
              padding: '16px 24px',
              fontSize: '18px',
              fontWeight: '600',
              cursor: 'pointer',
              transition: 'all 0.3s ease',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '12px'
            }}
            onMouseOver={(e) => e.target.style.background = '#e67e00'}
            onMouseOut={(e) => e.target.style.background = '#ff8a00'}
          >
            👨‍💼 Admin Login
          </button>

          <button
            onClick={() => navigate('/user-login')}
            style={{
              background: '#ff8a00',
              color: '#fff',
              border: 'none',
              borderRadius: '12px',
              padding: '16px 24px',
              fontSize: '18px',
              fontWeight: '600',
              cursor: 'pointer',
              transition: 'all 0.3s ease',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '12px'
            }}
            onMouseOver={(e) => e.target.style.background = '#e67e00'}
            onMouseOut={(e) => e.target.style.background = '#ff8a00'}
          >
            👤 User Login
          </button>
        </div>

      </div>
    </div>
  );
}
