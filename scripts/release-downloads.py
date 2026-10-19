#!/usr/bin/env python3
"""Read public GitHub release ZIP download counts; does not measure active users."""
import argparse
import csv
from datetime import datetime, timezone
import json
import re
import sys
from urllib.request import Request, urlopen


def rows_for(releases, fetched_at):
    for release in releases:
        if release.get('draft'):
            continue
        for asset in release.get('assets', []):
            name = asset.get('name', '')
            if not re.fullmatch(r'Squat-(?:for-Mac-)?[0-9][A-Za-z0-9.-]*-(arm64|x86_64|universal)\.zip', name):
                continue
            count = asset.get('download_count')
            if not isinstance(count, int) or count < 0:
                raise ValueError('Download count unavailable for asset ' + name)
            yield [fetched_at, release['tag_name'], asset['id'], name, count]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('owner')
    parser.add_argument('repository')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*', args.owner) or not re.fullmatch(r'[A-Za-z0-9_.-]+', args.repository):
        parser.error('Invalid GitHub owner or repository')
    fetched_at = datetime.now(timezone.utc).isoformat()
    writer = csv.writer(sys.stdout)
    writer.writerow(['fetched_at_utc', 'tag', 'asset_id', 'filename', 'download_count'])
    for page in range(1, 101):
        url = f'https://api.github.com/repos/{args.owner}/{args.repository}/releases?per_page=100&page={page}'
        request = Request(url, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'Squat-release-stats'})
        with urlopen(request, timeout=20) as response:
            releases = json.load(response)
        if not isinstance(releases, list):
            raise ValueError('Unexpected GitHub response')
        writer.writerows(rows_for(releases, fetched_at))
        if len(releases) < 100:
            break
    else:
        raise RuntimeError('Pagination limit reached; output may be incomplete')


if __name__ == '__main__':
    main()
