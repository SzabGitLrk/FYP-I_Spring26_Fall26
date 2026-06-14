import React from 'react';

export default function Navbar({ currentView, onNavigate }) {
  return (
    <nav className="fixed top-0 left-0 right-0 z-[100] flex items-center justify-between p-4 sm:p-5">
      {/* Left: logo + wordmark */}
      <div 
        className="flex items-center gap-2 cursor-pointer"
        onClick={() => onNavigate && onNavigate('DASHBAORD')}
      >
        <svg width="26" height="26" viewBox="0 0 256 256" fill="#ffffff">
          <path d="M 256 256 L 128 256 L 0 128 L 128 128 Z M 256 128 L 128 128 L 0 0 L 128 0 Z" />
        </svg>
        <span className="text-white text-2xl font-playfair italic">DIVS</span>
      </div>

      {/* Center pill — hidden below md */}
      <div className="hidden md:flex absolute left-1/2 -translate-x-1/2 bg-black/20 backdrop-blur-md border border-black/30 rounded-full px-2 py-2 items-center gap-1 z-[200]">
      {['DASHBAORD', 'IMAGE DETECTION', 'VIDEO DETECTION', 'ABOUT'].map((label) => (
          <button
            key={label}
            onClick={() => onNavigate && onNavigate(label)}
            className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors ${
              currentView === label
                ? 'bg-indigo-500/40 text-white shadow-[0_0_15px_rgba(99,102,241,0.5)]'
                : 'text-white/80 hover:bg-indigo-500/20 hover:text-white'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      {/* Right: hamburger (mobile) */}
      <div className="flex items-center gap-3">
        {/* Mobile hamburger */}
        <button className="md:hidden flex flex-col gap-1.5 p-1">
          <span className="block w-6 h-0.5 bg-white rounded" />
          <span className="block w-6 h-0.5 bg-white rounded" />
          <span className="block w-6 h-0.5 bg-white rounded" />
        </button>
      </div>
    </nav>
  );
}
