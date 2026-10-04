// Builds heide-feeds.n8n.json from the files in src/.
// Run: node build.js
// The JSON is the file you import into n8n. Edit src/*.js, then run this again.

const fs = require('fs');
const path = require('path');

const read = (f) => fs.readFileSync(path.join(__dirname, 'src', f), 'utf8');

// lib.js ends with a guarded "module.exports" for the tests. Remove it for n8n.
const lib = read('lib.js').replace(/\nif \(typeof module[\s\S]*$/, '\n');

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

// Node IDs use the 0000...04xx range. The dithmarschen workflow uses 0000...01xx to 03xx.
const nodes = [
  {
    parameters: { httpMethod: 'GET', path: 'heide/alle-artikel', responseMode: 'responseNode', options: {} },
    id: '00000000-0000-4000-8000-000000000400',
    name: 'Webhook alle-artikel',
    type: 'n8n-nodes-base.webhook',
    typeVersion: 2,
    position: [0, 300],
    webhookId: '00000000-0000-4000-8000-000000000401',
  },
  {
    parameters: { jsCode: read('config.js'), mode: 'runOnceForAllItems' },
    id: '00000000-0000-4000-8000-000000000402', name: 'Config', type: 'n8n-nodes-base.code', typeVersion: 2, position: [300, 300],
  },
  ifNode('00000000-0000-4000-8000-000000000403', 'Needs fetch?', '={{ $json.needsFetch }}', [560, 300]),
  {
    parameters: {
      url: '={{ $json.url }}',
      sendHeaders: true,
      headerParameters: { parameters: [{ name: 'User-Agent', value: '={{ $json.userAgent }}' }] },
      options: { timeout: 20000, response: { response: { fullResponse: true, neverError: true, responseFormat: 'text' } } },
    },
    id: '00000000-0000-4000-8000-000000000404', name: 'Fetch source page', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, position: [820, 200],
  },
  {
    parameters: { jsCode: `${lib}\n${read('glue.js')}`, mode: 'runOnceForAllItems' },
    id: '00000000-0000-4000-8000-000000000405', name: 'Build feed', type: 'n8n-nodes-base.code', typeVersion: 2, position: [1080, 200],
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
    id: '00000000-0000-4000-8000-000000000406', name: 'Respond', type: 'n8n-nodes-base.respondToWebhook', typeVersion: 1.1, position: [1340, 300],
  },
  ifNode('00000000-0000-4000-8000-000000000407', 'Failed?', '={{ $json.failed }}', [1340, 100]),
  {
    parameters: {},
    id: '00000000-0000-4000-8000-000000000408', name: 'Notify (wire up later)', type: 'n8n-nodes-base.noOp', typeVersion: 1, position: [1600, 0],
    notes: 'Replace this node with a mail, chat or push node. $json.reason tells what failed.',
  },
];

const link = (node) => ({ node, type: 'main', index: 0 });
const connections = {
  'Webhook alle-artikel': { main: [[link('Config')]] },
  Config: { main: [[link('Needs fetch?')]] },
  'Needs fetch?': { main: [[link('Fetch source page')], [link('Respond')]] },
  'Fetch source page': { main: [[link('Build feed')]] },
  'Build feed': { main: [[link('Respond'), link('Failed?')]] },
  'Failed?': { main: [[link('Notify (wire up later)')], []] },
};

const workflow = {
  name: 'Heide RSS feed',
  nodes,
  connections,
  settings: { executionOrder: 'v1' },
  active: false,
};

fs.writeFileSync(path.join(__dirname, 'heide-feeds.n8n.json'), JSON.stringify(workflow, null, 2) + '\n');
console.log(`wrote heide-feeds.n8n.json (${nodes.length} nodes)`);
