import urllib.request, json

def q(query):
    url = 'http://localhost:9091/api/v1/query?query=' + urllib.request.quote(query)
    d = json.loads(urllib.request.urlopen(url).read())
    return d['data']['result']

print('=== AWS metrics in local Prometheus ===')
for r in q('node_memory_MemTotal_bytes{instance=~".*observability.*"}'):
    print('  MemTotal:', round(int(r['value'][1])/1024/1024, 1), 'MiB')
for r in q('node_memory_MemAvailable_bytes{instance=~".*observability.*"}'):
    print('  MemAvailable:', round(int(r['value'][1])/1024/1024, 1), 'MiB')
for r in q('node_load1{instance=~".*observability.*"}'):
    print('  Load 1m:', r['value'][1])
for r in q('(node_memory_SwapTotal_bytes{instance=~".*observability.*"} - node_memory_SwapFree_bytes{instance=~".*observability.*"})'):
    print('  Swap used:', round(int(r['value'][1])/1024/1024, 1), 'MiB')
print('=== Pipeline status ===')
for r in q('up{instance=~".*observability.*"}'):
    print('  %s -> %s' % (r['metric'].get('instance','?'), 'UP' if r['value'][1]=='1' else 'DOWN'))
