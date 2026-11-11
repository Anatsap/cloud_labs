import http from 'k6/http';
import { check, sleep } from 'k6';
const BASE_URL = __ENV.BASE_URL;         
const PASSWORD = __ENV.ADMIN_PASSWORD;    
const N = Number(__ENV.VUS || 80);        
const quick = __ENV.QUICK === '1';       

export const options = {
  stages: [
    { duration: quick ? '10s' : '3m', target: N },
    { duration: quick ? '20s' : '5m', target: N },
    { duration: quick ? '10s' : '2m', target: 0 },
  ],
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

export function setup() {
  const res = http.post(
    `${BASE_URL}/api/login`,
    JSON.stringify({ username: 'admin', password: PASSWORD }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  if (res.status !== 200) {
    throw new Error('Не вдалося увійти, код ' + res.status);
  }
  return { token: res.json('access_token') };
}

export default function (data) {
  const car = JSON.stringify({
    brand: 'BMW',
    engine_power: 300,
    max_speed: 250,
    img: 'x.jpg',
    type: 'sedan',
    price: 10000 + Math.floor(Math.random() * 90000),
  });
  const created = http.post(`${BASE_URL}/api/cars/`, car, {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${data.token}`,
    },
  });
  check(created, { 'запис: код 201': (r) => r.status === 201 });
  if (created.status !== 201) {
    sleep(1);
    return; 
  }
  const id = created.json('id'); 
  const randomId = 1 + Math.floor(Math.random() * id); 
  sleep(0.2);

  const reads = [
    '/api/cars/?limit=20',               
    `/api/cars/${id}`,                   
    '/api/cars/?limit=20&sort=high',     
    '/api/cars/?limit=20&type=sedan',   
    `/api/cars/${randomId}`,             
    '/api/cars/total_price/',            
    '/api/cars/?limit=20&search=bmw',    
    '/api/cars/?limit=20',               
    `/api/cars/${id}`,                   
  ];
  for (const path of reads) {
    const res = http.get(BASE_URL + path);
    check(res, { 'читання: код 200': (r) => r.status === 200 });
    sleep(0.2);
  }
}
