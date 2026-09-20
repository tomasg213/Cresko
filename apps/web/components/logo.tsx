export function Logo({ className = "h-6 w-6" }: { className?: string }) {
  return (
    <svg viewBox="0 0 200 200" className={className} aria-hidden="true">
      <g fill="none" stroke="#2A9D8F" strokeLinecap="round" strokeLinejoin="round">
        <path d="M 140 50 A 65 65 0 1 0 140 150" strokeWidth={18} />
        <path
          d="M 115 75 C 115 65, 85 65, 85 85 C 85 105, 115 95, 115 115 C 115 135, 85 135, 85 125"
          strokeWidth={12}
        />
        <line x1="100" y1="58" x2="100" y2="142" strokeWidth={10} />
      </g>
    </svg>
  );
}