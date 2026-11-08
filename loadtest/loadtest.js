// Навантажувальний тест для Cars API (k6).
// Кожен віртуальний користувач повторює цикл: 1 запис + 9 читань.
// Запуск: ./loadtest/run.sh

import http from 'k6/http';
import { check, sleep } from 'k6';

// Ці значення передає run.sh
const BASE_URL = __ENV.BASE_URL;          // адреса сервісу
const PASSWORD = __ENV.ADMIN_PASSWORD;    // пароль адміністратора API
const N = Number(__ENV.VUS || 40);        // N: скільки користувачів на сталому навантаженні
const quick = __ENV.QUICK === '1';        // QUICK=1 це короткий пробний запуск (40 секунд)

export const options = {
  // Три фази: наростання, стале навантаження, спад
  stages: [
    { duration: quick ? '10s' : '3m', target: N },
    { duration: quick ? '20s' : '5m', target: N },
    { duration: quick ? '10s' : '2m', target: 0 },
  ],
  // Які значення показати в підсумку (med це p50)
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

// Виконується один раз на початку: входимо й отримуємо токен
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

// Виконується в циклі кожним віртуальним користувачем
export default function (data) {
  // 1. ЗАПИС: створюємо автомобіль (потрібен токен)
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
    return; // запис не вдався, читання цього разу пропускаємо
  }
  const id = created.json('id'); // id щойно створеного автомобіля
  const randomId = 1 + Math.floor(Math.random() * id); // випадковий id від 1 до id
  sleep(0.2);

  // 2. ЧИТАННЯ: 9 запитів
  const reads = [
    '/api/cars/?limit=20',               // список
    `/api/cars/${id}`,                   // щойно створений автомобіль
    '/api/cars/?limit=20&sort=high',     // список, найдорожчі першими
    '/api/cars/?limit=20&type=sedan',    // список з фільтром
    `/api/cars/${randomId}`,             // випадковий автомобіль
    '/api/cars/total_price/',            // сума цін
    '/api/cars/?limit=20&search=bmw',    // пошук
    '/api/cars/?limit=20',               // список ще раз
    `/api/cars/${id}`,                   // щойно створений ще раз
  ];
  for (const path of reads) {
    const res = http.get(BASE_URL + path);
    check(res, { 'читання: код 200': (r) => r.status === 200 });
    sleep(0.2);
  }
}
