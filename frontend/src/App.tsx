import { useState } from 'react'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'

function App() {
  const [depositAmount, setDepositAmount] = useState('')
  const { address, isConnected } = useAccount()
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()

  const handleDeposit = () => {
    if (!depositAmount) return

    console.log(depositAmount)
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        backgroundColor: '#f3f4f6',
        paddingTop: '2rem',
        paddingBottom: '2rem',
      }}
    >
      <div
        style={{
          maxWidth: '56rem',
          margin: '0 auto',
          paddingLeft: '1rem',
          paddingRight: '1rem',
        }}
      >
        <h1
          style={{
            fontSize: '2.25rem',
            fontWeight: '700',
            textAlign: 'center',
            marginBottom: '2rem',
            color: '#1f2937',
          }}
        >
          Halyard Finance
        </h1>

        <div
          style={{
            backgroundColor: 'white',
            borderRadius: '0.5rem',
            boxShadow:
              '0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
            padding: '1.5rem',
            marginBottom: '1.5rem',
          }}
        >
          <h2
            style={{
              fontSize: '1.5rem',
              fontWeight: '600',
              marginBottom: '1rem',
              color: '#1f2937',
            }}
          >
            Wallet Connection
          </h2>

          {!isConnected ? (
            <button
              onClick={() => connect({ connector: injected() })}
              style={{
                backgroundColor: '#3b82f6',
                color: 'white',
                fontWeight: '700',
                padding: '0.5rem 1rem',
                borderRadius: '0.25rem',
                border: 'none',
                cursor: 'pointer',
                transition: 'background-color 0.2s',
              }}
              onMouseOver={(e) =>
                (e.currentTarget.style.backgroundColor = '#2563eb')
              }
              onMouseOut={(e) =>
                (e.currentTarget.style.backgroundColor = '#3b82f6')
              }
            >
              Connect Wallet
            </button>
          ) : (
            <div
              style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}
            >
              <p style={{ color: '#6b7280' }}>
                Connected:{' '}
                <span style={{ fontFamily: 'monospace', fontSize: '0.875rem' }}>
                  {address}
                </span>
              </p>
              <button
                onClick={() => disconnect()}
                style={{
                  backgroundColor: '#ef4444',
                  color: 'white',
                  fontWeight: '700',
                  padding: '0.5rem 1rem',
                  borderRadius: '0.25rem',
                  border: 'none',
                  cursor: 'pointer',
                  transition: 'background-color 0.2s',
                }}
                onMouseOver={(e) =>
                  (e.currentTarget.style.backgroundColor = '#dc2626')
                }
                onMouseOut={(e) =>
                  (e.currentTarget.style.backgroundColor = '#ef4444')
                }
              >
                Disconnect
              </button>
            </div>
          )}
        </div>

        {isConnected && (
          <div
            style={{
              backgroundColor: 'white',
              borderRadius: '0.5rem',
              boxShadow:
                '0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
              padding: '1.5rem',
              marginBottom: '1.5rem',
            }}
          >
            <h2
              style={{
                fontSize: '1.5rem',
                fontWeight: '600',
                marginBottom: '1rem',
                color: '#1f2937',
              }}
            >
              Deposit
            </h2>

            <div
              style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}
            >
              <div>
                <label
                  style={{
                    display: 'block',
                    fontSize: '0.875rem',
                    fontWeight: '500',
                    color: '#374151',
                    marginBottom: '0.5rem',
                  }}
                >
                  Amount (in wei)
                </label>
                <input
                  type='number'
                  value={depositAmount}
                  onChange={(e) => setDepositAmount(e.target.value)}
                  placeholder='1000000000000000000'
                  style={{
                    width: '100%',
                    padding: '0.5rem 0.75rem',
                    border: '1px solid #d1d5db',
                    borderRadius: '0.375rem',
                    outline: 'none',
                    transition: 'border-color 0.2s, box-shadow 0.2s',
                  }}
                  onFocus={(e) => {
                    e.target.style.borderColor = '#3b82f6'
                    e.target.style.boxShadow =
                      '0 0 0 3px rgba(59, 130, 246, 0.1)'
                  }}
                  onBlur={(e) => {
                    e.target.style.borderColor = '#d1d5db'
                    e.target.style.boxShadow = 'none'
                  }}
                />
              </div>

              <button
                onClick={handleDeposit}
                disabled={!depositAmount}
                style={{
                  backgroundColor: !depositAmount ? '#9ca3af' : '#10b981',
                  color: 'white',
                  fontWeight: '700',
                  padding: '0.5rem 1rem',
                  borderRadius: '0.25rem',
                  border: 'none',
                  cursor: !depositAmount ? 'not-allowed' : 'pointer',
                  transition: 'background-color 0.2s',
                }}
                onMouseOver={(e) => {
                  if (depositAmount) {
                    e.currentTarget.style.backgroundColor = '#059669'
                  }
                }}
                onMouseOut={(e) => {
                  if (depositAmount) {
                    e.currentTarget.style.backgroundColor = '#10b981'
                  }
                }}
              >
                Deposit
              </button>
            </div>
          </div>
        )}

        {isConnected && (
          <div
            style={{
              backgroundColor: 'white',
              borderRadius: '0.5rem',
              boxShadow:
                '0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
              padding: '1.5rem',
            }}
          >
            <h2
              style={{
                fontSize: '1.5rem',
                fontWeight: '600',
                marginBottom: '1rem',
                color: '#1f2937',
              }}
            >
              Balance
            </h2>
            <p style={{ fontSize: '1.125rem' }}>
              Your balance:{' '}
              <span style={{ fontFamily: 'monospace' }}>0 wei</span>
            </p>
          </div>
        )}
      </div>
    </div>
  )
}

export default App
