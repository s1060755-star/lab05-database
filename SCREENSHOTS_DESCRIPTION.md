# Опис скріншотів до лабораторної роботи №5

Усього відібрано та задокументовано **20** скріншотів у папці `final_shots/`:

## 1. Знімок екрана 2026-11-24 163353.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 163353.png`
- **Опис:** Підключення до сервера баз даних PostgreSQL 16 у pgAdmin 4 (Object Explorer), перегляд панелі моніторингу Dashboard (Activity: Server sessions, Transactions per second, Tuples in, Tuples out, Block I/O).

## 2. Знімок екрана 2026-11-24 163423.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 163423.png`
- **Опис:** Розгортання вузла Databases (1) та бази даних postgres у pgAdmin 4 із відображенням системних розділів об'єктів (Casts, Catalogs, Event Triggers, Extensions, Foreign Data Wrappers, Languages, Publications, Schemas, Subscriptions) і метрик бази.

## 3. Знімок екрана 2026-11-24 163616.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 163616.png`
- **Опис:** Перегляд схеми public у базі даних postgres у pgAdmin 4 (Tables, Views, Functions, Procedures, Sequences, Trigger Functions) разом із фіксацією активності сесій та транзакцій на вкладці Dashboard.

## 4. Знімок екрана 2026-11-24 163753.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 163753.png`
- **Опис:** Моніторинг роботи схеми public та бази даних postgres у pgAdmin 4 (Database sessions, Transactions per second, Tuples out, Block I/O) під час виконання запитів.

## 5. Знімок екрана 2026-11-24 164537.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 164537.png`
- **Опис:** Відкрите вікно Query Tool (postgres/postgres@PostgreSQL 16) із підготовленим SQL-запитом створення тестової таблиці CREATE TABLE test_check (id SERIAL PRIMARY KEY, name TEXT NOT NULL);

## 6. Знімок екрана 2026-11-24 164622.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 164622.png`
- **Опис:** Успішне виконання запиту створення тестової таблиці test_check у pgAdmin 4 (Query returned successfully in 436 msec., статус CREATE TABLE на вкладці Messages).

## 7. Знімок екрана 2026-11-24 164706.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 164706.png`
- **Опис:** Виконання запиту видалення тестової таблиці DROP TABLE IF EXISTS test_check; (Query returned successfully in 91 msec., статус DROP TABLE) для очищення бази даних після перевірки.

## 8. Знімок екрана 2026-11-24 164935.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 164935.png`
- **Опис:** Створення таблиці workouts із зовнішніми ключами на trainers та members і вставка тестових даних INSERT INTO members, trainers, workouts (INSERT 0 2, Query returned successfully in 114 msec.).

## 9. Знімок екрана 2026-11-24 165054.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 165054.png`
- **Опис:** Перевірка вмісту таблиці workouts запитом SELECT * FROM workouts; у Data Output (Ранковий стретчинг, Базове силове тренуван..., 2026-11-25 09:00:00 та 2026-11-25 18:30:00).

## 10. Знімок екрана 2026-11-24 165148.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 165148.png`
- **Опис:** Виконання об'єднувального SQL-запиту JOIN між таблицями workouts w, members m та trainers t (w.member_id = m.member_id, w.trainer_id = t.trainer_id) із виведенням учасників, тренерів та спеціалізацій.

## 11. Знімок екрана 2026-11-24 170454.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 170454.png`
- **Опис:** Підготовлений у Query Tool транзакційний SQL-скрипт (BEGIN; UPDATE subscriptions SET price = 1750.00 WHERE member_id = 1; SELECT ...; ROLLBACK; SELECT ...;) для перевірки відкату змін у таблиці subscriptions та поточні рядки у Data Output (1500.00 і 2200.00).

## 12. Знімок екрана 2026-11-24 170732.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 170732.png`
- **Опис:** Результат виконання транзакційного скрипта BEGIN ... UPDATE subscriptions ... ROLLBACK у pgAdmin 4 (Successfully run. Total query runtime: 183 msec. 2 rows affected.) зі збереженням початкових цін абонементів.

## 13. Знімок екрана 2026-11-24 170831.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 170831.png`
- **Опис:** Виконання запиту з групуванням GROUP BY та умовою HAVING COUNT(*) >= 1 AND workouts_count >= 1 по представленню public.member_summary із виведенням учасників, планів, вартості та кількості тренувань.

## 14. Знімок екрана 2026-11-24 170923.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 170923.png`
- **Опис:** Створення індексів idx_workouts_member_id та idx_workouts_trainer_id (CREATE INDEX IF NOT EXISTS) і виконання LEFT JOIN між members та subscriptions із CASE-виразом статусу абонемента (subscription_status = 'Активний').

## 15. Знімок екрана 2026-11-24 171105.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 171105.png`
- **Опис:** Створення або оновлення представлення CREATE OR REPLACE VIEW public.trainer_summary з агрегатами COUNT(w.workout_id), COUNT(DISTINCT w.member_id), MIN(w.workout_date), MAX(w.workout_date) та LEFT JOIN із workouts.

## 16. Знімок екрана 2026-11-24 171145.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 171145.png`
- **Опис:** Перегляд визначення представлення public.trainer_summary і результатів вибірки в Data Output у pgAdmin 4 (Олена Коваль, Максим Шевчен..., true, 1500.00, 2200.00, workouts_count = 1).

## 17. Знімок екрана 2026-11-24 171156.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 171156.png`
- **Опис:** Підтвердження успішного виконання SQL-скрипта зі створення public.trainer_summary та вибірок по представленнях у pgAdmin 4 (Successfully run. Total query runtime: 308 msec. 2 rows affected.).

## 18. Знімок екрана 2026-11-24 171331.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 171331.png`
- **Опис:** Запити до системних каталогів information_schema.tables та pg_indexes (WHERE schemaname = 'public' AND tablename = 'workouts') із виведенням індексів таблиці workouts у Data Output.

## 19. Знімок екрана 2026-11-24 171447.png
- **Файл:** `final_shots/Знімок екрана 2026-11-24 171447.png`
- **Опис:** Зведений аналітичний запит зі скалярними підзапитами для підрахунку кількості учасників (2), тренерів (2), тренувань (2), абонементів (2) і доходу за активними абонементами (active_revenue = 3700.00).

## 20. Знімок екрана 2026-11-24 171551.jpg
- **Файл:** `final_shots/Знімок екрана 2026-11-24 171551.jpg`
- **Опис:** Загальний вигляд вікна pgAdmin 4 після виконання зведеного аналітичного запиту (Total rows: 1, Query complete 00:00:00.148, active_revenue = 3700.00) та розгорнутих таблиць у схемі public.