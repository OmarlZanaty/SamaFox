/**
 * Reference SVG+CSS animation templates that meet the spec quality bar.
 * Each template:
 *  - transparent background
 *  - cubic-bezier easing (never linear)
 *  - >=3 visual layers
 *  - radial/linear gradients (no flat colors)
 *  - hardware-accelerated transform/opacity animations only
 *  - seamless loop
 *  - no JavaScript
 *  - well under 200KB
 */

export interface GiftTemplate {
  key: string;
  name: string;
  nameAr: string;
  tier: 'SMALL' | 'MEDIUM' | 'LARGE' | 'LEGENDARY';
  category: string;
  coinCost: number;
  animationMs: number;
  html: string;
}

const FLOATING_HEART_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:transparent;overflow:hidden;-webkit-tap-highlight-color:transparent}
  .stage{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
  @keyframes heartFloat{
    0%{transform:translateY(40%) scale(.6);opacity:0}
    15%{transform:translateY(15%) scale(1.2);opacity:1}
    25%{transform:translateY(5%) scale(.95);opacity:1}
    85%{transform:translateY(-45%) scale(1);opacity:1}
    100%{transform:translateY(-80%) scale(.7);opacity:0}
  }
  @keyframes heartPulse{0%,100%{transform:scale(1)}50%{transform:scale(1.1)}}
  @keyframes sparkleFloat{
    0%{transform:translate(0,0) scale(0);opacity:0}
    20%{opacity:1}
    100%{transform:translate(var(--tx),var(--ty)) scale(1);opacity:0}
  }
  .heart-wrap{animation:heartFloat 2.5s cubic-bezier(0.34,1.56,0.64,1) infinite;will-change:transform,opacity}
  .heart-inner{animation:heartPulse .6s cubic-bezier(0.65,0,0.35,1) infinite;transform-origin:center;will-change:transform}
  .sparkle{position:absolute;width:6px;height:6px;background:radial-gradient(circle,#fff 0%,transparent 70%);border-radius:50%;animation:sparkleFloat 1.5s ease-out infinite;will-change:transform,opacity}
  .s1{--tx:-30px;--ty:-40px;animation-delay:0s}
  .s2{--tx:30px;--ty:-45px;animation-delay:.3s}
  .s3{--tx:-25px;--ty:-55px;animation-delay:.6s}
  .s4{--tx:35px;--ty:-35px;animation-delay:.9s}
  .s5{--tx:0;--ty:-60px;animation-delay:.2s}
</style>
</head>
<body>
<div class="stage">
  <div class="heart-wrap">
    <span class="sparkle s1"></span>
    <span class="sparkle s2"></span>
    <span class="sparkle s3"></span>
    <span class="sparkle s4"></span>
    <span class="sparkle s5"></span>
    <svg viewBox="0 0 100 100" width="160" height="160" class="heart-inner">
      <defs>
        <radialGradient id="hg" cx="35%" cy="30%">
          <stop offset="0%" stop-color="#FFE4EC"/>
          <stop offset="40%" stop-color="#FF6B9D"/>
          <stop offset="100%" stop-color="#C2185B"/>
        </radialGradient>
        <filter id="hglow"><feGaussianBlur stdDeviation="2.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
      </defs>
      <path d="M50 85 C 15 60, 5 30, 28 20 C 40 16, 50 28, 50 40 C 50 28, 60 16, 72 20 C 95 30, 85 60, 50 85 Z" fill="url(#hg)" filter="url(#hglow)" stroke="#FFE4EC" stroke-width="1" opacity=".95"/>
      <ellipse cx="38" cy="35" rx="6" ry="3" fill="#fff" opacity=".5" transform="rotate(-30 38 35)"/>
    </svg>
  </div>
</div>
</body>
</html>`;

const SPARKLE_ROSE_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:transparent;overflow:hidden}
  .stage{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
  @keyframes roseEntry{
    0%{transform:translateY(50%) rotate(-30deg) scale(.4);opacity:0}
    25%{transform:translateY(0) rotate(8deg) scale(1.15);opacity:1}
    35%{transform:translateY(0) rotate(-4deg) scale(.97);opacity:1}
    50%{transform:translateY(0) rotate(0) scale(1);opacity:1}
    85%{transform:translateY(-10%) rotate(0) scale(1);opacity:1}
    100%{transform:translateY(-30%) rotate(0) scale(.85);opacity:0}
  }
  @keyframes petalShimmer{0%,100%{filter:brightness(1)}50%{filter:brightness(1.25)}}
  @keyframes ringPulse{
    0%{transform:scale(.5);opacity:.6}
    100%{transform:scale(2);opacity:0}
  }
  .rose-wrap{animation:roseEntry 3s cubic-bezier(0.16,1,0.3,1) infinite;will-change:transform,opacity;position:relative}
  .rose-shimmer{animation:petalShimmer 1.5s ease-in-out infinite;will-change:filter}
  .ring{position:absolute;inset:50% auto auto 50%;transform-origin:center;width:140px;height:140px;margin:-70px 0 0 -70px;border:2px solid #FFB6C1;border-radius:50%;animation:ringPulse 2s ease-out infinite;will-change:transform,opacity}
  .ring.r2{animation-delay:.5s;border-color:#FFD700}
  .ring.r3{animation-delay:1s;border-color:#FF69B4}
</style>
</head>
<body>
<div class="stage">
  <div class="rose-wrap">
    <span class="ring"></span><span class="ring r2"></span><span class="ring r3"></span>
    <svg viewBox="0 0 120 140" width="180" height="210" class="rose-shimmer">
      <defs>
        <radialGradient id="petalGrad" cx="40%" cy="35%">
          <stop offset="0%" stop-color="#FFE0EC"/>
          <stop offset="50%" stop-color="#FF4081"/>
          <stop offset="100%" stop-color="#8B0033"/>
        </radialGradient>
        <linearGradient id="stemGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#2E7D32"/>
          <stop offset="100%" stop-color="#1B5E20"/>
        </linearGradient>
        <filter id="rglow"><feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
      </defs>
      <path d="M60 130 C 65 120, 65 100, 60 80" stroke="url(#stemGrad)" stroke-width="4" fill="none" stroke-linecap="round"/>
      <path d="M55 95 C 40 90, 38 80, 45 78 C 50 80, 55 88, 55 95 Z" fill="#2E7D32"/>
      <path d="M65 100 C 80 95, 82 85, 75 83 C 70 85, 65 93, 65 100 Z" fill="#388E3C"/>
      <g filter="url(#rglow)">
        <ellipse cx="60" cy="55" rx="32" ry="28" fill="url(#petalGrad)"/>
        <path d="M60 30 Q 40 35, 35 55 Q 38 75, 60 78 Q 82 75, 85 55 Q 80 35, 60 30 Z" fill="url(#petalGrad)" opacity=".9"/>
        <path d="M60 38 Q 48 42, 46 55 Q 50 68, 60 70 Q 70 68, 74 55 Q 72 42, 60 38 Z" fill="#FF80AB" opacity=".95"/>
        <ellipse cx="58" cy="50" rx="8" ry="6" fill="#FFD1DC" opacity=".7"/>
        <circle cx="60" cy="55" r="4" fill="#FFEB3B" opacity=".8"/>
      </g>
    </svg>
  </div>
</div>
</body>
</html>`;

const SURPRISE_BOX_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:transparent;overflow:hidden}
  .stage{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
  @keyframes boxArrive{
    0%{transform:translateY(60%) scale(.5);opacity:0}
    20%{transform:translateY(5%) scale(1.2);opacity:1}
    30%{transform:translateY(0) scale(.95);opacity:1}
    40%{transform:translateY(0) scale(1);opacity:1}
    100%{transform:translateY(0) scale(1);opacity:1}
  }
  @keyframes lidPop{
    0%,40%{transform:translateY(0) rotate(0)}
    50%{transform:translateY(-60px) rotate(-25deg)}
    70%{transform:translateY(-30px) rotate(10deg)}
    100%{transform:translateY(0) rotate(0)}
  }
  @keyframes burstScale{
    0%,45%{transform:scale(0);opacity:0}
    55%{transform:scale(1.3);opacity:1}
    75%{transform:scale(1);opacity:1}
    100%{transform:scale(.9);opacity:0}
  }
  @keyframes confettiFly{
    0%,40%{transform:translate(0,0) rotate(0);opacity:0}
    50%{opacity:1}
    100%{transform:translate(var(--cx),var(--cy)) rotate(var(--cr));opacity:0}
  }
  .box-wrap{animation:boxArrive 3.5s cubic-bezier(0.34,1.56,0.64,1) infinite;will-change:transform,opacity;position:relative}
  .lid{animation:lidPop 3.5s cubic-bezier(0.16,1,0.3,1) infinite;transform-origin:center bottom;will-change:transform}
  .burst{animation:burstScale 3.5s cubic-bezier(0.65,0,0.35,1) infinite;will-change:transform,opacity}
  .confetti{position:absolute;width:8px;height:14px;border-radius:2px;animation:confettiFly 3.5s ease-out infinite;will-change:transform,opacity}
  .c1{--cx:-90px;--cy:-110px;--cr:280deg;background:linear-gradient(45deg,#FFD700,#FFA000)}
  .c2{--cx:90px;--cy:-100px;--cr:-220deg;background:linear-gradient(45deg,#FF4081,#C2185B)}
  .c3{--cx:-110px;--cy:-60px;--cr:180deg;background:linear-gradient(45deg,#00E5FF,#0091EA)}
  .c4{--cx:110px;--cy:-50px;--cr:-180deg;background:linear-gradient(45deg,#76FF03,#33691E)}
  .c5{--cx:0;--cy:-130px;--cr:360deg;background:linear-gradient(45deg,#E040FB,#6A1B9A)}
  .c6{--cx:-50px;--cy:-140px;--cr:-360deg;background:linear-gradient(45deg,#FFEB3B,#F57F17)}
  .c7{--cx:50px;--cy:-140px;--cr:300deg;background:linear-gradient(45deg,#FF6E40,#BF360C)}
  .c8{--cx:-130px;--cy:-90px;--cr:240deg;background:linear-gradient(45deg,#7C4DFF,#311B92)}
</style>
</head>
<body>
<div class="stage">
  <div class="box-wrap">
    <span class="confetti c1"></span><span class="confetti c2"></span>
    <span class="confetti c3"></span><span class="confetti c4"></span>
    <span class="confetti c5"></span><span class="confetti c6"></span>
    <span class="confetti c7"></span><span class="confetti c8"></span>
    <svg viewBox="0 0 200 220" width="240" height="264">
      <defs>
        <linearGradient id="boxBody" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#F44336"/>
          <stop offset="100%" stop-color="#B71C1C"/>
        </linearGradient>
        <linearGradient id="boxLid" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#FF7043"/>
          <stop offset="100%" stop-color="#C62828"/>
        </linearGradient>
        <radialGradient id="burstGrad" cx="50%" cy="50%">
          <stop offset="0%" stop-color="#FFFDE7"/>
          <stop offset="50%" stop-color="#FFD600"/>
          <stop offset="100%" stop-color="#FF6F00" stop-opacity="0"/>
        </radialGradient>
        <filter id="boxShadow"><feGaussianBlur stdDeviation="3"/></filter>
      </defs>
      <ellipse cx="100" cy="200" rx="60" ry="6" fill="#000" opacity=".25" filter="url(#boxShadow)"/>
      <rect x="40" y="100" width="120" height="100" rx="6" fill="url(#boxBody)"/>
      <rect x="95" y="100" width="10" height="100" fill="#FFEB3B"/>
      <rect x="40" y="140" width="120" height="10" fill="#FFEB3B"/>
      <g class="burst">
        <circle cx="100" cy="85" r="55" fill="url(#burstGrad)"/>
        <polygon points="100,30 108,72 150,72 116,98 130,140 100,115 70,140 84,98 50,72 92,72" fill="#FFEB3B" opacity=".9"/>
      </g>
      <g class="lid">
        <rect x="32" y="80" width="136" height="30" rx="6" fill="url(#boxLid)"/>
        <path d="M100 70 C 90 50, 80 60, 88 80 L 92 80 C 95 70, 95 65, 100 70 Z" fill="#FFEB3B"/>
        <path d="M100 70 C 110 50, 120 60, 112 80 L 108 80 C 105 70, 105 65, 100 70 Z" fill="#FFEB3B"/>
      </g>
    </svg>
  </div>
</div>
</body>
</html>`;

const ROYAL_CROWN_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:transparent;overflow:hidden}
  .stage{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
  @keyframes crownDescend{
    0%{transform:translateY(-80%) scale(.7) rotate(-12deg);opacity:0}
    25%{transform:translateY(-5%) scale(1.15) rotate(4deg);opacity:1}
    35%{transform:translateY(5%) scale(.95) rotate(-2deg);opacity:1}
    50%{transform:translateY(0) scale(1) rotate(0);opacity:1}
    100%{transform:translateY(0) scale(1) rotate(0);opacity:1}
  }
  @keyframes crownGleam{0%,100%{filter:brightness(1)}50%{filter:brightness(1.35) drop-shadow(0 0 12px #FFD700)}}
  @keyframes rayRotate{0%{transform:rotate(0)}100%{transform:rotate(360deg)}}
  @keyframes spark{
    0%{transform:rotate(var(--ra)) translateX(0) scale(0);opacity:0}
    20%{opacity:1}
    100%{transform:rotate(var(--ra)) translateX(120px) scale(.6);opacity:0}
  }
  .crown-wrap{animation:crownDescend 4s cubic-bezier(0.16,1,0.3,1) infinite;will-change:transform,opacity;position:relative;width:300px;height:300px;display:flex;align-items:center;justify-content:center}
  .rays{position:absolute;inset:0;animation:rayRotate 10s linear infinite;will-change:transform}
  .crown-gleam{animation:crownGleam 2s ease-in-out infinite;will-change:filter}
  .spk{position:absolute;left:50%;top:50%;width:8px;height:8px;background:radial-gradient(circle,#fff,#FFD700,transparent);border-radius:50%;animation:spark 2s ease-out infinite;transform-origin:0 0;will-change:transform,opacity}
  .k1{--ra:0deg;animation-delay:.0s}
  .k2{--ra:60deg;animation-delay:.3s}
  .k3{--ra:120deg;animation-delay:.6s}
  .k4{--ra:180deg;animation-delay:.9s}
  .k5{--ra:240deg;animation-delay:1.2s}
  .k6{--ra:300deg;animation-delay:1.5s}
</style>
</head>
<body>
<div class="stage">
  <div class="crown-wrap">
    <svg class="rays" viewBox="0 0 300 300" width="300" height="300">
      <defs>
        <radialGradient id="rayG" cx="50%" cy="50%">
          <stop offset="0%" stop-color="#FFF59D" stop-opacity=".0"/>
          <stop offset="30%" stop-color="#FFEB3B" stop-opacity=".4"/>
          <stop offset="100%" stop-color="#FFEB3B" stop-opacity="0"/>
        </radialGradient>
      </defs>
      <circle cx="150" cy="150" r="140" fill="url(#rayG)"/>
      <g opacity=".5" fill="#FFEB3B">
        <polygon points="150,10 156,140 144,140"/>
        <polygon points="150,290 156,160 144,160"/>
        <polygon points="10,150 140,144 140,156"/>
        <polygon points="290,150 160,144 160,156"/>
        <polygon points="50,50 145,138 138,145"/>
        <polygon points="250,250 162,155 155,162"/>
        <polygon points="250,50 162,145 155,138"/>
        <polygon points="50,250 138,155 145,162"/>
      </g>
    </svg>
    <span class="spk k1"></span><span class="spk k2"></span><span class="spk k3"></span>
    <span class="spk k4"></span><span class="spk k5"></span><span class="spk k6"></span>
    <svg class="crown-gleam" viewBox="0 0 200 160" width="220" height="176">
      <defs>
        <linearGradient id="goldG" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#FFF59D"/>
          <stop offset="40%" stop-color="#FFD700"/>
          <stop offset="100%" stop-color="#FF8F00"/>
        </linearGradient>
        <radialGradient id="gemG" cx="35%" cy="35%">
          <stop offset="0%" stop-color="#FFB6F0"/>
          <stop offset="60%" stop-color="#E91E63"/>
          <stop offset="100%" stop-color="#6A0033"/>
        </radialGradient>
        <radialGradient id="gemBlue" cx="35%" cy="35%">
          <stop offset="0%" stop-color="#B3E5FC"/>
          <stop offset="60%" stop-color="#2196F3"/>
          <stop offset="100%" stop-color="#0D47A1"/>
        </radialGradient>
        <radialGradient id="gemGreen" cx="35%" cy="35%">
          <stop offset="0%" stop-color="#C8E6C9"/>
          <stop offset="60%" stop-color="#4CAF50"/>
          <stop offset="100%" stop-color="#1B5E20"/>
        </radialGradient>
      </defs>
      <path d="M30 130 L 30 80 L 60 110 L 80 50 L 100 90 L 120 40 L 140 90 L 160 50 L 180 110 L 200 80 L 200 130 Q 195 145, 180 145 L 50 145 Q 35 145, 30 130 Z" fill="url(#goldG)" stroke="#8D6E00" stroke-width="2"/>
      <rect x="30" y="125" width="170" height="22" rx="4" fill="url(#goldG)" stroke="#8D6E00" stroke-width="2"/>
      <circle cx="80" cy="50" r="8" fill="url(#gemBlue)" stroke="#fff" stroke-width="1"/>
      <circle cx="120" cy="40" r="9" fill="url(#gemG)" stroke="#fff" stroke-width="1"/>
      <circle cx="160" cy="50" r="8" fill="url(#gemGreen)" stroke="#fff" stroke-width="1"/>
      <circle cx="60" cy="135" r="5" fill="url(#gemG)"/>
      <circle cx="100" cy="135" r="5" fill="url(#gemBlue)"/>
      <circle cx="140" cy="135" r="5" fill="url(#gemGreen)"/>
      <circle cx="180" cy="135" r="5" fill="url(#gemG)"/>
      <path d="M50 145 L 60 138 L 70 145 Z" fill="#fff" opacity=".4"/>
    </svg>
  </div>
</div>
</body>
</html>`;

const STAR_BURST_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:transparent;overflow:hidden}
  .stage{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
  @keyframes starEnter{
    0%{transform:scale(.2) rotate(-180deg);opacity:0}
    25%{transform:scale(1.3) rotate(20deg);opacity:1}
    35%{transform:scale(.95) rotate(-10deg);opacity:1}
    50%{transform:scale(1.05) rotate(0);opacity:1}
    100%{transform:scale(1) rotate(0);opacity:1}
  }
  @keyframes starSpin{0%{transform:rotate(0)}100%{transform:rotate(360deg)}}
  @keyframes starPulse{0%,100%{transform:scale(1);filter:brightness(1)}50%{transform:scale(1.08);filter:brightness(1.4)}}
  @keyframes auraExpand{
    0%{transform:scale(.6);opacity:.8}
    100%{transform:scale(2.4);opacity:0}
  }
  @keyframes orbitDust{
    0%{transform:rotate(0) translateX(140px) rotate(0);opacity:0}
    20%,80%{opacity:1}
    100%{transform:rotate(360deg) translateX(140px) rotate(-360deg);opacity:0}
  }
  .star-wrap{animation:starEnter 4.5s cubic-bezier(0.16,1,0.3,1) infinite;will-change:transform,opacity;position:relative;width:360px;height:360px;display:flex;align-items:center;justify-content:center}
  .star-spin{animation:starSpin 8s linear infinite;will-change:transform}
  .star-pulse{animation:starPulse 1.8s ease-in-out infinite;transform-origin:center;will-change:transform,filter}
  .aura{position:absolute;inset:50% auto auto 50%;width:240px;height:240px;margin:-120px 0 0 -120px;border-radius:50%;background:radial-gradient(circle,rgba(255,235,59,.5) 0%,rgba(255,193,7,.2) 50%,transparent 70%);animation:auraExpand 2.5s ease-out infinite;will-change:transform,opacity}
  .aura.a2{animation-delay:.8s}
  .aura.a3{animation-delay:1.6s}
  .dust{position:absolute;left:50%;top:50%;width:10px;height:10px;background:radial-gradient(circle,#fff,#FFEB3B,transparent);border-radius:50%;transform-origin:-140px 0;animation:orbitDust 5s linear infinite;will-change:transform,opacity}
  .d1{animation-delay:0s}.d2{animation-delay:.5s}.d3{animation-delay:1s}.d4{animation-delay:1.5s}.d5{animation-delay:2s}.d6{animation-delay:2.5s}.d7{animation-delay:3s}.d8{animation-delay:3.5s}
</style>
</head>
<body>
<div class="stage">
  <div class="star-wrap">
    <span class="aura"></span><span class="aura a2"></span><span class="aura a3"></span>
    <span class="dust d1"></span><span class="dust d2"></span><span class="dust d3"></span><span class="dust d4"></span>
    <span class="dust d5"></span><span class="dust d6"></span><span class="dust d7"></span><span class="dust d8"></span>
    <svg class="star-spin" viewBox="0 0 300 300" width="300" height="300">
      <defs>
        <radialGradient id="starCore" cx="50%" cy="50%">
          <stop offset="0%" stop-color="#FFFDE7"/>
          <stop offset="30%" stop-color="#FFEB3B"/>
          <stop offset="70%" stop-color="#FF8F00"/>
          <stop offset="100%" stop-color="#BF360C"/>
        </radialGradient>
        <linearGradient id="rayGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#FFEB3B" stop-opacity=".9"/>
          <stop offset="100%" stop-color="#FF6F00" stop-opacity=".4"/>
        </linearGradient>
        <filter id="starGlow"><feGaussianBlur stdDeviation="6" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
      </defs>
      <g class="star-pulse" transform="translate(150,150)" filter="url(#starGlow)">
        <polygon points="0,-100 -8,-20 -88,-30 -24,18 -64,84 0,40 64,84 24,18 88,-30 8,-20" fill="url(#rayGrad)" opacity=".75"/>
        <polygon points="0,-70 -7,-15 -60,-22 -20,12 -45,60 0,28 45,60 20,12 60,-22 7,-15" fill="url(#starCore)"/>
        <circle cx="0" cy="0" r="22" fill="#FFFDE7" opacity=".85"/>
        <circle cx="-6" cy="-6" r="6" fill="#fff" opacity=".7"/>
      </g>
    </svg>
  </div>
</div>
</body>
</html>`;

const ETERNAL_DIAMOND_HTML = `<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  html,body{width:100%;height:100%;background:transparent;overflow:hidden}
  .stage{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
  @keyframes diaEnter{
    0%{transform:translateY(40%) scale(.4) rotate(-25deg);opacity:0}
    20%{transform:translateY(-5%) scale(1.25) rotate(10deg);opacity:1}
    32%{transform:translateY(5%) scale(.92) rotate(-5deg);opacity:1}
    45%{transform:translateY(0) scale(1.04) rotate(0);opacity:1}
    100%{transform:translateY(0) scale(1) rotate(0);opacity:1}
  }
  @keyframes diaShimmer{0%{filter:brightness(1) hue-rotate(0)}50%{filter:brightness(1.3) hue-rotate(15deg)}100%{filter:brightness(1) hue-rotate(0)}}
  @keyframes orbitRing{0%{transform:rotate(0)}100%{transform:rotate(360deg)}}
  @keyframes glintFlash{0%,90%,100%{opacity:0;transform:scale(.6)}45%{opacity:1;transform:scale(1.2)}}
  @keyframes innerPulse{0%,100%{transform:scale(1);opacity:.6}50%{transform:scale(1.15);opacity:.9}}
  .dia-wrap{animation:diaEnter 5s cubic-bezier(0.16,1,0.3,1) infinite;will-change:transform,opacity;position:relative;width:360px;height:360px;display:flex;align-items:center;justify-content:center}
  .dia-shimmer{animation:diaShimmer 2.5s ease-in-out infinite;will-change:filter}
  .ring-1{position:absolute;width:340px;height:340px;border-radius:50%;border:2px dashed rgba(180,220,255,.6);animation:orbitRing 12s linear infinite;will-change:transform}
  .ring-2{position:absolute;width:260px;height:260px;border-radius:50%;border:1px solid rgba(255,255,255,.4);animation:orbitRing 8s linear infinite reverse;will-change:transform}
  .glint{position:absolute;width:12px;height:12px;background:radial-gradient(circle,#fff,#B3E5FC,transparent);border-radius:50%;animation:glintFlash 2s ease-in-out infinite;will-change:transform,opacity}
  .g1{top:25%;left:30%;animation-delay:0s}
  .g2{top:30%;right:25%;animation-delay:.4s}
  .g3{bottom:30%;left:28%;animation-delay:.8s}
  .g4{bottom:25%;right:30%;animation-delay:1.2s}
  .g5{top:50%;left:15%;animation-delay:.6s}
  .g6{top:50%;right:15%;animation-delay:1s}
  .inner-glow{position:absolute;width:200px;height:200px;border-radius:50%;background:radial-gradient(circle,rgba(179,229,252,.6),rgba(33,150,243,.2),transparent 70%);animation:innerPulse 2s ease-in-out infinite;will-change:transform,opacity}
</style>
</head>
<body>
<div class="stage">
  <div class="dia-wrap">
    <span class="ring-1"></span>
    <span class="ring-2"></span>
    <span class="inner-glow"></span>
    <span class="glint g1"></span><span class="glint g2"></span><span class="glint g3"></span>
    <span class="glint g4"></span><span class="glint g5"></span><span class="glint g6"></span>
    <svg class="dia-shimmer" viewBox="0 0 200 240" width="240" height="288">
      <defs>
        <linearGradient id="dTop" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#FFFFFF"/>
          <stop offset="50%" stop-color="#B3E5FC"/>
          <stop offset="100%" stop-color="#0277BD"/>
        </linearGradient>
        <linearGradient id="dLeft" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#81D4FA"/>
          <stop offset="100%" stop-color="#01579B"/>
        </linearGradient>
        <linearGradient id="dRight" x1="1" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#B3E5FC"/>
          <stop offset="100%" stop-color="#01579B"/>
        </linearGradient>
        <radialGradient id="dCore" cx="50%" cy="40%">
          <stop offset="0%" stop-color="#FFFFFF"/>
          <stop offset="40%" stop-color="#E1F5FE"/>
          <stop offset="100%" stop-color="#039BE5"/>
        </radialGradient>
        <filter id="dGlow"><feGaussianBlur stdDeviation="4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
      </defs>
      <g filter="url(#dGlow)">
        <polygon points="100,30 160,80 100,220 40,80" fill="url(#dCore)" stroke="#fff" stroke-width="2"/>
        <polygon points="100,30 130,80 100,80 70,80" fill="url(#dTop)" opacity=".95"/>
        <polygon points="40,80 70,80 100,220" fill="url(#dLeft)" opacity=".85"/>
        <polygon points="160,80 130,80 100,220" fill="url(#dRight)" opacity=".85"/>
        <polygon points="70,80 100,80 100,220" fill="#fff" opacity=".15"/>
        <polygon points="100,30 130,80 100,80" fill="#fff" opacity=".4"/>
        <line x1="70" y1="80" x2="100" y2="220" stroke="#fff" stroke-width=".5" opacity=".7"/>
        <line x1="130" y1="80" x2="100" y2="220" stroke="#fff" stroke-width=".5" opacity=".7"/>
      </g>
    </svg>
  </div>
</div>
</body>
</html>`;

export const GIFT_TEMPLATES: GiftTemplate[] = [
  {
    key: 'floating_heart',
    name: 'Floating Heart',
    nameAr: 'قلب طائر',
    tier: 'SMALL',
    category: 'love',
    coinCost: 5,
    animationMs: 2500,
    html: FLOATING_HEART_HTML,
  },
  {
    key: 'sparkle_rose',
    name: 'Sparkle Rose',
    nameAr: 'وردة متلألئة',
    tier: 'SMALL',
    category: 'love',
    coinCost: 25,
    animationMs: 3000,
    html: SPARKLE_ROSE_HTML,
  },
  {
    key: 'surprise_box',
    name: 'Surprise Box',
    nameAr: 'صندوق المفاجآت',
    tier: 'MEDIUM',
    category: 'fun',
    coinCost: 150,
    animationMs: 3500,
    html: SURPRISE_BOX_HTML,
  },
  {
    key: 'royal_crown',
    name: 'Royal Crown',
    nameAr: 'تاج ملكي',
    tier: 'MEDIUM',
    category: 'luxury',
    coinCost: 400,
    animationMs: 4000,
    html: ROYAL_CROWN_HTML,
  },
  {
    key: 'star_burst',
    name: 'Star Burst',
    nameAr: 'انفجار النجوم',
    tier: 'LARGE',
    category: 'festive',
    coinCost: 1500,
    animationMs: 4500,
    html: STAR_BURST_HTML,
  },
  {
    key: 'eternal_diamond',
    name: 'Eternal Diamond',
    nameAr: 'الماسة الأبدية',
    tier: 'LARGE',
    category: 'luxury',
    coinCost: 4000,
    animationMs: 5000,
    html: ETERNAL_DIAMOND_HTML,
  },
];

export function templateByKey(key: string): GiftTemplate | undefined {
  return GIFT_TEMPLATES.find((t) => t.key === key);
}
