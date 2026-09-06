import asyncio
import sys
sys.path.insert(0, '.')

from app.services.scrapers.musical_chairs_scraper import scrape_musical_chairs

async def main():
    results = await scrape_musical_chairs()
    print(f"Total: {len(results)} oportunidades unicas")
    print()
    for r in results[:5]:
        print(f"  Tipo:    {r['type']}")
        print(f"  Titulo:  {r['title'][:80]}")
        print(f"  URL:     {r['source_url']}")
        print(f"  Instrum: {r['instruments']}")
        print()

asyncio.run(main())
