import React, { useRef, useEffect } from 'react';

const SPOTLIGHT_R = 260;

const BG_VIDEO_2 =
  'https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260411_104032_69319010-2458-492b-b04d-b40a5dfa4482.mp4';

function SpotlightVideoBackground({ cursorX, cursorY }) {
  const canvasRef = useRef(null);
  const overlayRef = useRef(null);

  // Resize canvas to window size
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const resize = () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
    };
    resize();
    window.addEventListener('resize', resize);
    return () => window.removeEventListener('resize', resize);
  }, []);

  // Draw gradient mask (opaque with a hole) and apply to overlay div
  useEffect(() => {
    const canvas = canvasRef.current;
    const overlayDiv = overlayRef.current;
    if (!canvas || !overlayDiv) return;

    const ctx = canvas.getContext('2d');
    
    // Fill entire canvas with opaque white
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = 'white';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // Punch out a soft hole at the cursor
    const grad = ctx.createRadialGradient(
      cursorX, cursorY, 0,
      cursorX, cursorY, SPOTLIGHT_R
    );
    grad.addColorStop(0,    'rgba(255,255,255,1)');
    grad.addColorStop(0.4,  'rgba(255,255,255,1)');
    grad.addColorStop(0.6,  'rgba(255,255,255,0.75)');
    grad.addColorStop(0.75, 'rgba(255,255,255,0.4)');
    grad.addColorStop(0.88, 'rgba(255,255,255,0.12)');
    grad.addColorStop(1,    'rgba(255,255,255,0)');

    ctx.globalCompositeOperation = 'destination-out';
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(cursorX, cursorY, SPOTLIGHT_R, 0, Math.PI * 2);
    ctx.fill();

    const dataUrl = canvas.toDataURL();
    overlayDiv.style.maskImage = `url(${dataUrl})`;
    overlayDiv.style.webkitMaskImage = `url(${dataUrl})`;
    overlayDiv.style.maskSize = '100% 100%';
    overlayDiv.style.webkitMaskSize = '100% 100%';
  }, [cursorX, cursorY]);

  return (
    <>
      <canvas
        ref={canvasRef}
        className="absolute inset-0 pointer-events-none"
        style={{ display: 'none' }}
      />
      {/* 1. Base Sharp Video (z-0) */}
      <div className="absolute inset-0 z-0 pointer-events-none overflow-hidden bg-[#1a1a2e]">
        <video
          src={BG_VIDEO_2}
          autoPlay
          muted
          loop
          playsInline
          className="absolute inset-0 w-full h-full object-cover hero-zoom"
        />
      </div>
      {/* 2. Blurry Dark Overlay with Hole-Punch Mask (z-10) */}
      <div
        ref={overlayRef}
        className="absolute inset-0 z-10 pointer-events-none backdrop-blur-xl bg-black/60"
      />
    </>
  );
}

import Navbar from './Navbar';

export default function HeroSection({ onNavigate }) {
  const mouseRef = useRef({ x: -999, y: -999 });
  const smoothRef = useRef({ x: -999, y: -999 });
  const rafRef = useRef(null);
  const [cursorPos, setCursorPos] = React.useState({ x: -999, y: -999 });

  useEffect(() => {
    const onMove = (e) => {
      mouseRef.current = { x: e.clientX, y: e.clientY };
    };

    const loop = () => {
      smoothRef.current.x += (mouseRef.current.x - smoothRef.current.x) * 0.1;
      smoothRef.current.y += (mouseRef.current.y - smoothRef.current.y) * 0.1;
      setCursorPos({ x: smoothRef.current.x, y: smoothRef.current.y });
      rafRef.current = requestAnimationFrame(loop);
    };

    window.addEventListener('mousemove', onMove);
    rafRef.current = requestAnimationFrame(loop);

    return () => {
      window.removeEventListener('mousemove', onMove);
      cancelAnimationFrame(rafRef.current);
    };
  }, []);

  return (
    <div
      className="min-h-screen bg-white tracking-[-0.02em]"
      style={{ fontFamily: "'Inter', sans-serif" }}
    >
      <Navbar currentView="DASHBAORD" onNavigate={onNavigate} />

      {/* ── Hero Section ───────────────────────────────────────── */}
      <section
        className="relative w-full overflow-hidden h-screen bg-black/90"
        style={{ height: '100dvh' }}
      >
        {/* 1 & 2. Base Video & Blurry Overlay with Spotlight Mask (z-0 to z-10) */}
        <SpotlightVideoBackground cursorX={cursorPos.x} cursorY={cursorPos.y} />

        {/* 3. Heading (z-50) */}
        <div className="absolute z-50 top-[14%] left-0 right-0 flex flex-col items-center text-center px-5 pointer-events-none">
          <h1 className="text-white leading-[0.95]">
            <span
              className="block font-playfair italic font-normal text-5xl sm:text-7xl md:text-8xl hero-anim hero-reveal"
              style={{ letterSpacing: '-0.05em', animationDelay: '0.25s' }}
            >
              Unmasking
            </span>
            <span
              className="block font-normal text-5xl sm:text-7xl md:text-8xl -mt-1 hero-anim hero-reveal"
              style={{ letterSpacing: '-0.08em', animationDelay: '0.42s' }}
            >
              the digital truth
            </span>
          </h1>
        </div>

        {/* 4. Bottom-left paragraph (z-50) */}
        <div
          className="hidden sm:block absolute z-50 bottom-14 left-10 md:left-14 max-w-[260px] hero-anim hero-fade"
          style={{ animationDelay: '0.7s' }}
        >
          <p className="text-sm text-white/80 leading-relaxed">
            Our advanced neural networks analyze pixel-level artifacts, temporal inconsistencies, and frequency domain anomalies to distinguish authentic media from synthetic generation.
          </p>
        </div>

        {/* 5. Bottom-right block (z-50) */}
        <div
          className="absolute z-50 bottom-10 sm:bottom-24 left-5 right-5 sm:left-auto sm:right-10 md:right-14 max-w-full sm:max-w-[260px] flex flex-col items-start gap-4 sm:gap-5 hero-anim hero-fade"
          style={{ animationDelay: '0.85s' }}
        >
          <p className="text-xs sm:text-sm text-white/80 leading-relaxed">
            Experience real-time AI forensics. Upload your images or videos and let our deep learning models peel back the layers to reveal what's real and what's synthesized.
          </p>
          {/* <button 
            onClick={() => onNavigate('IMAGE DETECTION')}
            className="bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-medium px-7 py-3 rounded-full transition-all hover:scale-[1.03] active:scale-95 hover:shadow-lg hover:shadow-indigo-500/30"
          >
            Initialize Scanner
          </button> */}
        </div>
      </section>
    </div>
  );
}
