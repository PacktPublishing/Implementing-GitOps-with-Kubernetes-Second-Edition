// k6 2.x: load, stress, a shortened soak and a spike in one run. The thresholds
// turn the test into a pass/fail check: the Job fails if the SLO is not met.
// TARGET_URL defaults to the in-cluster stable Service. During a canary, point
// it at the public hostname so that traffic is split by the Gateway.
import http from 'k6/http';
import { check, sleep } from 'k6';

const cities = ['Zurich', 'Geneva', 'Milan', 'Berlin', 'Lisbon', 'Oslo', 'Vienna', 'Madrid'];

export const options = {
  stages: [
    { duration: '1m', target: 10 },  // load: expected traffic
    { duration: '3m', target: 50 },  // stress: well above it
    { duration: '5m', target: 50 },  // soak (shortened): hold and watch
    { duration: '30s', target: 200 }, // spike
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

export default function () {
  const city = cities[Math.floor(Math.random() * cities.length)];
  const res = http.get(`${__ENV.TARGET_URL}/api/weather?city=${city}`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.2);
}
