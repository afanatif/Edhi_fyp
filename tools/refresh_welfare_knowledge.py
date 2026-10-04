"""Download public official welfare pages into a small, offline search corpus.

Usage: python tools/refresh_welfare_knowledge.py
Only allowlisted hosts are fetched. robots.txt is respected, redirects are checked,
and failed refreshes retain the previous successful document. No user chat is sent.
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
import json
import urllib.request
import urllib.robotparser
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'assets' / 'knowledge' / 'welfare_sources.json'
HOSTS = {'www.edhi.org', 'edhi.org', 'www.chhipa.org', 'chhipa.org'}
PAGES = [
    ('Edhi', 'https://www.edhi.org/' + path)
    for path in ['about-us', 'ambulance', 'children', 'educational', 'graveyard',
                 'contact-us', 'punjab', 'sindh', 'kpk', 'zakat', 'sadqa']
] + [
    ('Chhipa', 'https://www.chhipa.org/' + path)
    for path in ['about-us/', 'contact-us/', 'services/chhipa-ambulance/',
                 'services/chhipa-dastarkhawan/', 'services/chhipa-home-orphanage/',
                 'services/chhipa-old-home/', 'services/chhipa-women-shelter-home/',
                 'services/chhipa-ration/', 'services/chhipa-morgue/',
                 'services/chhipa-jhoola/', 'services/chhipa-new-born-baby/',
                 'how-to-donate/donate-via-jazzcash/', 'how-to-donate/donate-via-easypaisa/']
]

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urllib.parse.urlparse(newurl).hostname not in HOSTS:
            raise ValueError('Redirect outside official source allowlist')
        return super().redirect_request(req, fp, code, msg, headers, newurl)

OPENER = urllib.request.build_opener(SafeRedirect())
AGENT = 'EdhiConnectKnowledge/1.0'

def download(url):
    request = urllib.request.Request(url, headers={'User-Agent': AGENT})
    with OPENER.open(request, timeout=25) as response:
        if 'text/' not in response.headers.get('Content-Type', ''):
            raise ValueError('Expected an HTML page')
        return response.read(2_000_000).decode('utf-8', errors='replace'), response.url

class Paragraphs(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip = 0
        self.block = None
        self.parts = []
        self.blocks = []
        self.title = ''
    def handle_starttag(self, tag, attrs):
        if tag in {'script', 'style', 'nav', 'footer', 'header', 'noscript', 'form'}:
            self.skip += 1
        if not self.skip and tag in {'p', 'h1', 'h2', 'h3', 'title'}:
            self.block = tag
            self.parts = []
    def handle_endtag(self, tag):
        if self.block == tag:
            text = ' '.join(' '.join(self.parts).split())
            if tag == 'title': self.title = text
            elif len(text) >= 35: self.blocks.append(text)
            self.block = None
        if tag in {'script', 'style', 'nav', 'footer', 'header', 'noscript', 'form'}:
            self.skip = max(0, self.skip - 1)
    def handle_data(self, data):
        if self.block and not self.skip: self.parts.append(data)

def main():
    existing = json.loads(OUTPUT.read_text(encoding='utf-8')) if OUTPUT.exists() else {'documents': []}
    retained = {doc['requestedUrl']: doc for doc in existing['documents']}
    robots = {}
    for host in sorted({urllib.parse.urlparse(url).hostname for _, url in PAGES}):
        parser = urllib.robotparser.RobotFileParser()
        try:
            text, _ = download('https://' + host + '/robots.txt')
            parser.parse(text.splitlines())
            robots[host] = parser
        except Exception as error:
            print(f'robots unavailable for {host}: {type(error).__name__}; skipping host')
    def scrape(item):
        provider, url = item
        host = urllib.parse.urlparse(url).hostname
        if host not in robots or not robots[host].can_fetch(AGENT, url):
            return url, None, 'robots disallowed or unavailable'
        try:
            html, final_url = download(url)
            parser = Paragraphs()
            parser.feed(html)
            blocks = list(dict.fromkeys(parser.blocks))
            # Avoid generic footers and donation prompts dominating retrieval.
            blocks = [b for b in blocks if not any(x in b.lower() for x in
                      ['join our supporter', 'stay informed about our', 'copyright', 'designed & developed'])]
            if sum(map(len, blocks)) < 150: raise ValueError('Insufficient source content')
            return url, {'provider': provider, 'requestedUrl': url, 'url': final_url,
                         'title': parser.title or provider, 'fetchedAt': datetime.now(timezone.utc).isoformat(),
                         'paragraphs': [b[:2000] for b in blocks[:80]]}, None
        except Exception as error:
            return url, None, type(error).__name__
    # One worker per provider avoids a burst of concurrent requests to one host.
    succeeded = 0
    with ThreadPoolExecutor(max_workers=2) as executor:
        for url, document, error in executor.map(scrape, PAGES):
            if document:
                retained[url] = document
                succeeded += 1
                print('Downloaded:', url)
            else: print('Retained previous / skipped:', url, error)
    if not succeeded:
        raise SystemExit('No official pages refreshed; previous corpus unchanged.')
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({'documents': list(retained.values())}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Saved {len(retained)} source documents; {succeeded} refreshed.')

if __name__ == '__main__': main()
