import { writeFileSync } from 'node:fs';
const names = ['package','users','laptop','ticket','truck','scan-barcode','file-spreadsheet','file-text','check','moon','sheet','list-checks','map-pin','calendar-clock','hash','tag'];
const out = {};
for (const n of names) {
  const { __iconNode } = await import(`/Users/arpan/webdev/mockup/node_modules/lucide-react/dist/esm/icons/${n}.js`);
  out[n] = __iconNode.map(([tag, attrs]) => `<${tag} ${Object.entries(attrs).filter(([k]) => k !== 'key').map(([k, v]) => `${k}="${v}"`).join(' ')}/>`).join('');
}
writeFileSync(process.argv[2], JSON.stringify(out));
