// Builds dithmarschen-feeds.n8n.json from the files in src/.
// Run: node build.js
// The JSON is the file you import into n8n. Edit src/*.js, then run this again.

const fs = require('fs');
const path = require('path');

const read = (f) => fs.readFileSync(path.join(__dirname, 'src', f), 'utf8');

// lib.js ends with a guarded "module.exports" for the tests. Remove it for n8n.
const lib = read('lib.js').replace(/\nif \(typeof module[\s\S]*$/, '\n');

const FEEDS = ['pressemitteilungen', 'bekanntmachungen', 'ausschreibungen', 'terminkalender'];

const webhooks = FEEDS.map((feed, i) => ({
  parameters: { httpMethod: 'GET', path: `dithmarschen/${feed}`, responseMode: 'responseNode', options: {} },
  id: `00000000-0000-4000-8000-00000000010${i}`,
  name: `Webhook ${feed}`,
  type: 'n8n-nodes-base.webhook',
  typeVersion: 2,
  position: [0, 200 * i],
  webhookId: `00000000-0000-4000-8000-00000000020${i}`,
}));

const ifNode = (id, name, leftValue, position) => ({
  parameters: {
    conditions: {
      options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{
        id: `${id}-cond`,
        leftValue,
        rightValue: '',
        operator: { type: 'boolean', operation: 'true', singleValue: true },
      }],
      combinator: 'and',
    },
    options: {},
  },
  id, name, type: 'n8n-nodes-base.if', typeVersion: 2.2, position,
});

const nodes = [
  ...webhooks,
  {
    parameters: { jsCode: read('config.js'), mode: 'runOnceForAllItems' },
    id: '00000000-0000-4000-8000-000000000301', name: 'Config', type: 'n8n-nodes-base.code', typeVersion: 2, position: [300, 300],
  },
  ifNode('00000000-0000-4000-8000-000000000302', 'Needs fetch?', '={{ $json.needsFetch }}', [560, 300]),
  {
    parameters: {
      url: '={{ $json.url }}',
      sendHeaders: true,
      headerParameters: { parameters: [{ name: 'User-Agent', value: '={{ $json.userAgent }}' }] },
      options: { timeout: 20000, response: { response: { fullResponse: true, neverError: true, responseFormat: 'text' } } },
    },
    id: '00000000-0000-4000-8000-000000000303', name: 'Fetch source page', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, position: [820, 200],
  },
  {
    parameters: { jsCode: `${lib}\n${read('glue.js')}`, mode: 'runOnceForAllItems' },
    id: '00000000-0000-4000-8000-000000000304', name: 'Build feed', type: 'n8n-nodes-base.code', typeVersion: 2, position: [1080, 200],
  },
  {
    parameters: {
      respondWith: 'text',
      responseBody: '={{ $json.body }}',
      options: {
        responseCode: '={{ $json.status }}',
        responseHeaders: { entries: [{ name: 'Content-Type', value: '={{ $json.contentType }}' }] },
      },
    },
    id: '00000000-0000-4000-8000-000000000305', name: 'Respond', type: 'n8n-nodes-base.respondToWebhook', typeVersion: 1.1, position: [1340, 300],
  },
  ifNode('00000000-0000-4000-8000-000000000306', 'Failed?', '={{ $json.failed }}', [1340, 100]),
  {
    parameters: {},
    id: '00000000-0000-4000-8000-000000000307', name: 'Notify (wire up later)', type: 'n8n-nodes-base.noOp', typeVersion: 1, position: [1600, 0],
    notes: 'Replace this node with a mail, chat or push node. $json.reason tells what failed.',
  },
];

const link = (node) => ({ node, type: 'main', index: 0 });
const connections = {
  Config: { main: [[link('Needs fetch?')]] },
  'Needs fetch?': { main: [[link('Fetch source page')], [link('Respond')]] },
  'Fetch source page': { main: [[link('Build feed')]] },
  'Build feed': { main: [[link('Respond'), link('Failed?')]] },
  'Failed?': { main: [[link('Notify (wire up later)')], []] },
};
for (const w of webhooks) connections[w.name] = { main: [[link('Config')]] };

const workflow = {
  name: 'Dithmarschen RSS feeds',
  nodes,
  connections,
  settings: { executionOrder: 'v1' },
  active: false,
};

fs.writeFileSync(path.join(__dirname, 'dithmarschen-feeds.n8n.json'), JSON.stringify(workflow, null, 2) + '\n');
console.log(`wrote dithmarschen-feeds.n8n.json (${nodes.length} nodes)`);
