import http from 'k6/http';
import { check, sleep } from 'k6';
import { randomString } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// Set via environment variable: k6 run -e API_ENDPOINT=https://your-api.execute-api.region.amazonaws.com load-test.js
const API_ENDPOINT = __ENV.API_ENDPOINT;
if (!API_ENDPOINT) {
  throw new Error('API_ENDPOINT environment variable is required');
}

export const options = {
  // how many virtual users (VUs) over time
  stages: [
    { duration: '10s', target: 5 },
    { duration: '30s', target: 10},
    { duration: '10s', target: 0},
  ],
  // pass/fail criteria for the test
  thresholds: {
    http_req_failed: ['rate<0.6'], // pass if less than 60% of requests
    http_req_duration: ['p(95)<2000'], // pass if 95th percentile latency < 2
  },
};

export default function () {
  // request body which simulates a file upload
  const payload = JSON.stringify({
    filename: `load-${randomString(8)}.txt`,
    content: `Load test data ${Date.now()}`,
  });

  // headers
  const params = {
    headers: { 'Content-Type': 'application/json'},
  };

  // make request and post to API gateway or process endpoint
  const res = http.post(`${API_ENDPOINT}/process`, payload, params);

  // need to verify response and check records pass/fail before reporting
  check(res, {
  'status is 200': (r) => r.status === 200,
  'status is 500 (chaos state)': (r) => r.status === 500,
});

  // wait before next request (this gives us around 2 requests per second per user)
  sleep(0.5)
}
