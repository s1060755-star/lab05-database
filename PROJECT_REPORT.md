# Звіт з лабораторної роботи 05: Керування БД, оптимізація продуктивності та автоматизація

**Виконала:** Скоп'юк Олександра  
**Група:** ІПЗ-31  
**СУБД:** PostgreSQL 16 (pgAdmin 4, `psql`)  
**База даних та схема:** `postgres`, схема `public`  
**Каталог проєкту:** `C:\Users\Олександра\Desktop\SportsClub_PG16`  
**Репозиторій:** `https://github.com/s1060755-star/lab05-database.git`

---

## 1. Результати аналізу продуктивності до та після оптимізації

- Для аналізу продуктивності та планів виконання запитів застосовувала команди `EXPLAIN` та `EXPLAIN (ANALYZE, BUFFERS)` (з обгортанням змін у `BEGIN; ... ROLLBACK;`).
- До оптимізації на таблицях без цільових індексів або при неселективних умовах переважав `Sequential Scan`, зростали оціночна вартість (`cost`), реальний час (`actual time`) та кількість прочитаних буферів.
- Після оптимізації створення індексів, часткових індексів, оновлення статистики (`ANALYZE`) та перебудова індексів (`REINDEX`) дозволили оптимізатору використовувати `Index Scan`, `Index Only Scan` або `Bitmap Index Scan`.
- Зафіксовані показники у проєкті (`03_final_summary.sql`): `members_count = 2`, `trainers_count = 2`, `workouts_count = 2`, `subscriptions_count = 2`, `active_revenue = 3700.00` (тренери `1` та `2`, дати `2026-11-25 09:00:00` і `2026-11-25 18:30:00`).

### Команди аналізу продуктивності та оптимізації

```sql
-- Оновлення статистики оптимізатора
ANALYZE;

-- Аналіз запиту з реальним часом та буферами
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    w.workout_id,
    w.workout_date,
    w.member_id,
    w.trainer_id
FROM public.workouts w
WHERE w.trainer_id = 1
ORDER BY w.workout_date DESC;

-- Безпечна перевірка зміни даних у межах транзакції з відкатом
BEGIN;
UPDATE subscriptions
SET price = 1750.00
WHERE member_id = 1;
SELECT member_id, plan_name, price FROM subscriptions ORDER BY member_id;
ROLLBACK;
SELECT member_id, plan_name, price FROM subscriptions ORDER BY member_id;
2. Опис створених індексів з обґрунтуванням їх необхідності
Створила індекси idx_workouts_member_id на workouts(member_id) та idx_workouts_trainer_id на workouts(trainer_id) для прискорення JOIN, фільтрації за WHERE та агрегації по клієнтах і тренерах (оскільки PostgreSQL не створює індекси автоматично для FOREIGN KEY).

Перевірила первинні ключі (members_pkey, subscriptions_pkey, trainers_pkey, workouts_pkey), які забезпечують унікальність записів та індексний доступ.

Застосувала часткові індекси (CREATE INDEX ... WHERE ...), які індексують лише потрібну підмножину рядків за незмінним (IMMUTABLE) предикатом.

Команди створення та обслуговування індексів
SQL
CREATE INDEX IF NOT EXISTS idx_workouts_member_id
ON workouts (member_id);

CREATE INDEX IF NOT EXISTS idx_workouts_trainer_id
ON workouts (trainer_id);

-- Приклад часткового індексу з IMMUTABLE-умовою
CREATE INDEX IF NOT EXISTS idx_subscriptions_high_price
ON public.subscriptions (member_id, price)
WHERE price >= 2000;

-- Перебудова індексів таблиці
REINDEX TABLE public.workouts;
3. SQL код представлень, тригерів та перевірених запитів
У схемі public бази postgres створила та перевірила таблиці (members, trainers, workouts, subscriptions) та представлення (member_summary, trainer_summary).

Перевірила логіку класифікації тарифів через CASE WHEN ('Преміум-рівень', 'Базовий рівень', 'Без абонемента'), перевірку актуальності абонементів за s.is_active AND s.valid_until >= CURRENT_DATE, агрегацію через GROUP BY та HAVING і відкат змін через BEGIN ... ROLLBACK.

Команди представлень, аудиту та тригерів
SQL
CREATE OR REPLACE VIEW public.trainer_summary AS
SELECT
    t.trainer_id,
    t.full_name AS trainer_name,
    t.specialization,
    COUNT(w.workout_id) AS workouts_count,
    COUNT(DISTINCT w.member_id) AS unique_members_count,
    MIN(w.workout_date) AS first_workout_at,
    MAX(w.workout_date) AS last_workout_at
FROM trainers t
LEFT JOIN workouts w ON t.trainer_id = w.trainer_id
GROUP BY t.trainer_id, t.full_name, t.specialization
ORDER BY workouts_count DESC, t.trainer_id;

SELECT
    member_name,
    plan_name,
    price,
    workouts_count,
    CASE
        WHEN price >= 2000 THEN 'Преміум-рівень'
        WHEN price > 0 THEN 'Базовий рівень'
        ELSE 'Без абонемента'
    END AS tariff_tier
FROM public.member_summary
ORDER BY price DESC, member_name;

CREATE TABLE IF NOT EXISTS public.audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    record_id INTEGER,
    old_values JSONB,
    new_values JSONB,
    changed_by VARCHAR(100),
    changed_at TIMESTAMP DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.log_subscription_audit()
RETURNS TRIGGER AS $$ BEGIN IF TG_OP = 'INSERT' THEN INSERT INTO public.audit_log (table_name, operation, record_id, new_values, changed_by) VALUES (TG_TABLE_NAME, TG_OP, NEW.subscription_id, to_jsonb(NEW), current_user); RETURN NEW; ELSIF TG_OP = 'UPDATE' THEN INSERT INTO public.audit_log (table_name, operation, record_id, old_values, new_values, changed_by) VALUES (TG_TABLE_NAME, TG_OP, NEW.subscription_id, to_jsonb(OLD), to_jsonb(NEW), current_user); RETURN NEW; ELSIF TG_OP = 'DELETE' THEN INSERT INTO public.audit_log (table_name, operation, record_id, old_values, changed_by) VALUES (TG_TABLE_NAME, TG_OP, OLD.subscription_id, to_jsonb(OLD), current_user); RETURN OLD; END IF; RETURN NULL; END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_subscription_audit ON public.subscriptions;
CREATE TRIGGER trg_subscription_audit
AFTER INSERT OR UPDATE OR DELETE ON public.subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.log_subscription_audit();
4. Скріншоти та опис виконання роботи
Підключення до сервера PostgreSQL 16 у pgAdmin 4 (Знімок екрана 2026-11-24 163353.png)

Опис: Відобразила вікно pgAdmin 4 із розгорнутим сервером PostgreSQL 16 (Databases, Login/Group Roles, Tablespaces) та вкладку Dashboard (Activity) із графіками сесій, транзакцій та звернень до блоків.

Перегляд бази даних postgres у pgAdmin 4 (Знімок екрана 2026-11-24 163423.png)

Опис: Розгорнула гілку Databases (1) -> postgres у PostgreSQL 16 із розділами Casts, Catalogs, Event Triggers, Extensions, Foreign Data Wrappers, Languages, Publications, Schemas, Subscriptions та панеллю активності бази.

Структура схеми public у базі postgres (Знімок екрана 2026-11-24 163616.png)

Опис: Показала розгорнуту гілку Schemas (1) -> public (Functions, Materialized Views, Procedures, Sequences, Tables, Trigger Functions, Views) та графіки роботи (Transactions per second, Tuples out, Block I/O).

Моніторинг активності бази даних у Dashboard (Знімок екрана 2026-11-24 163753.png)

Опис: Зафіксувала оновлений стан вкладки Dashboard (Activity) для бази postgres (PostgreSQL 16) із поточними графіками транзакцій та блоків.

Відкриття Query Tool для виконання SQL-запитів (Знімок екрана 2026-11-24 163828.png)

Опис: Відкрила Query Tool у pgAdmin 4 з підключенням postgres/postgres@PostgreSQL 16 та порожнім редактором запитів (No data output. Execute a query to get output.).

Навігація по базі postgres та схемі public (Знімок екрана 2026-11-24 164320.png)

Опис: Показала наближений фрагмент Object Explorer у pgAdmin 4 із виділеною базою postgres та розгорнутою схемою public.

SQL-запит створення тестової таблиці test_check (Знімок екрана 2026-11-24 164537.png)

Опис: У Query Tool (postgres/postgres@PostgreSQL 16*) сформувала запит CREATE TABLE test_check (id SERIAL PRIMARY KEY, name TEXT NOT NULL);.

Успішне створення таблиці test_check (Знімок екрана 2026-11-24 164622.png)

Опис: У вкладці Messages зафіксувала успішне виконання запиту: CREATE TABLE, Query returned successfully in 436 msec..

Видалення тестової таблиці test_check (Знімок екрана 2026-11-24 164706.png)

Опис: Виконала DROP TABLE IF EXISTS test_check; із повідомленням у Messages: DROP TABLE, Query returned successfully in 91 msec..

Створення таблиці workouts та вставка даних (Знімок екрана 2026-11-24 164935.png)

Опис: Показала створення таблиці workouts із зовнішніми ключами на trainers(trainer_id) і members(member_id) та вставку даних через INSERT INTO (members: Олена Коваль, Максим Шевченко; trainers: Ірина Бондар — «Фітнес і стретчинг», Андрій Ткаченко — «Силові тренування»; workouts: «Ранковий стретчинг» 2026-11-25 09:00:00 та «Базове силове тренування» 2026-11-25 18:30:00) із результатом INSERT 0 2 (Query returned successfully in 114 msec.).

Класифікація тарифних рівнів через CASE WHEN за даними public.member_summary (Знімок екрана 2026-11-24 170318.png)

Опис: Вивела Максим Шевченко (2200.00, workouts_count = 1, Преміум-рівень) та Олена Коваль (1500.00, workouts_count = 1, Базовий рівень) із сортуванням ORDER BY price DESC, member_name.

Перевірка транзакції та відкату змін BEGIN ... ROLLBACK (Знімок екрана 2026-11-24 170454.png та Знімок екрана 2026-11-24 170732.png)

Опис: Продемонструвала тестове оновлення subscriptions (price = 1750.00 для member_id = 1), відкат через ROLLBACK та збереження початкових значень (1500.00 і 2200.00, Successfully run. Total query runtime: 183 msec. 2 rows affected.).

Агрегація та фільтрація GROUP BY ... HAVING по public.member_summary (Знімок екрана 2026-11-24 170831.png)

Опис: Підтвердила вибірку по public.member_summary з GROUP BY і HAVING COUNT(*) >= 1 AND workouts_count >= 1 (Максим Шевченко — 2200.00, Олена Коваль — 1500.00, workouts_count = 1).

Створення індексів на workouts та перевірка актуальності абонементів (Знімок екрана 2026-11-24 170923.png)

Опис: Виконала CREATE INDEX IF NOT EXISTS idx_workouts_member_id ON workouts (member_id); та CREATE INDEX IF NOT EXISTS idx_workouts_trainer_id ON workouts (trainer_id); разом із LEFT JOIN між members і subscriptions та перевіркою s.is_active AND s.valid_until >= CURRENT_DATE (valid_until = 2026-12-24, is_active = true, subscription_status = 'Активний').

Створення представлення public.trainer_summary та перегляд public.member_summary (Знімок екрана 2026-11-24 171105.png та Знімок екрана 2026-11-24 171145.png)

Опис: Зафіксувала SQL-визначення CREATE OR REPLACE VIEW public.trainer_summary та результати вибірки по учасниках (Олена Коваль — 1500.00, Максим Шевченко — 2200.00, is_active = true, workouts_count = 1).

Підсумкові запити по public.trainer_summary та зведеним метрикам БД (Знімок екрана 2026-11-24 171551.jpg)

Опис: Підтвердила зведені показники бази даних: members_count = 2, trainers_count = 2, workouts_count = 2, subscriptions_count = 2, active_revenue = 3700.00 (Query complete 00:00:00.148).

Стан файлів проєкту, перегляд звіту та робота в оболонці (image_e83a0a.png, image_e83ac2.png, image_e83e1f.png, image_e8905a.png, image_e9047f.png)

Опис: Зафіксувала етапи створення та наповнення каталогу C:\Users\Олександра\Desktop\SportsClub_PG16 (03_final_summary, PROJECT_REPORT, psql_check_output, schema_objects), роботу з командами в терміналі та оформлення звіту PROJECT_REPORT.md.

5. Документація системи прав доступу та резервного копіювання
Налаштувала права користувачів і ролей через CREATE USER / CREATE ROLE, GRANT / REVOKE на рівні бази даних, схеми public, таблиць та представлень.

Виконала резервне копіювання та відновлення утилітами pg_dump, pg_restore або psql.

Команди керування правами, резервного копіювання та GitHub
SQL
CREATE USER report_viewer WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE postgres TO report_viewer;
GRANT USAGE ON SCHEMA public TO report_viewer;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO report_viewer;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO report_viewer;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO report_viewer;
PowerShell
# Резервне копіювання та відновлення
pg_dump -U postgres -d postgres -F c -f "C:\Users\Олександра\Desktop\SportsClub_PG16\backup_sportsclub.dump"
pg_dump -U postgres -d postgres -f "C:\Users\Олександра\Desktop\SportsClub_PG16\backup_sportsclub.sql"
createdb -U postgres test_restore
pg_restore -U postgres -d test_restore "C:\Users\Олександра\Desktop\SportsClub_PG16\backup_sportsclub.dump"

# Завантаження проєкту на GitHub
cd "C:\Users\Олександра\Desktop\SportsClub_PG16"
git init
git branch -M main
git add .
git commit -m "Add Lab 05 report, SQL commands, screenshots and answers"
git remote add origin [https://github.com/s1060755-star/lab05-database.git](https://github.com/s1060755-star/lab05-database.git)
git push -u origin main
6. Висновки та рекомендації
Під час виконання лабораторної роботи 05 я закріпила практичні навички роботи з PostgreSQL 16 у pgAdmin 4 та psql, створила й перевірила ключові об'єкти схеми public, індекси, представлення, транзакції з відкатом (BEGIN / ROLLBACK), тригери аудиту, систему прав доступу та резервне копіювання.

Я переконалася, що індексація та актуальна статистика оптимізатора зменшують витрати на обробку запитів, а представлення й транзакції роблять роботу з аналітикою та змінами даних безпечнішою й зручнішою.

Рекомендую регулярно оновлювати статистику (ANALYZE), контролювати використання індексів, дотримуватися принципу найменших привілеїв при видачі прав та періодично перевіряти відновлення даних із резервних копій.

7. Відповіді на контрольні запитання
1. Поясніть різницю між EXPLAIN та EXPLAIN ANALYZE. Коли краще використовувати кожну з цих команд?
Відповідь: EXPLAIN лише будує та показує оціночний план виконання запиту без його фактичного запуску. EXPLAIN ANALYZE фактично виконує запит і додає реальний час виконання (actual time) та фактичну кількість оброблених рядків/ітерацій. EXPLAIN зручно застосувати для попередньої оцінки плану без запуску запиту, а EXPLAIN ANALYZE (разом із BUFFERS) — для вимірювання реального часу виконання та читання буферів (з обов'язковим BEGIN; ... ROLLBACK; для запитів зміни даних).

2. Які типи індексів підтримує PostgreSQL? Опишіть ситуації, коли доцільно використовувати кожен тип.
Відповідь: PostgreSQL підтримує B-tree (стандартний тип для =, <, <=, >, >=, BETWEEN, IN, ORDER BY та префіксних умов), Hash (для простих порівнянь на рівність =), GiST (геометричні/просторові дані, діапазони, повнотекстовий пошук), SP-GiST (незбалансовані структури даних, дерева/префікси), GIN (масиви, JSONB, повнотекстовий пошук) та BRIN (дуже великі таблиці з природно впорядкованими фізично значеннями, наприклад датами чи послідовними ключами).

3. Що таке часткові індекси та в яких випадках їх використання дає найбільший виграш у продуктивності?
Відповідь: Частковий індекс створюється з умовою WHERE та індексує лише ті рядки таблиці, які відповідають незмінному (IMMUTABLE) предикату. Найбільший виграш він дає тоді, коли запити регулярно фільтрують стабільну або невелику підмножину даних (наприклад, активні абонементи чи замовлення вище заданого порогу), оскільки індекс менший за розміром, швидше оновлюється та ефективніше кешується.

4. Яка різниця між звичайним представленням (VIEW) та матеріалізованим представленням (MATERIALIZED VIEW)? Наведіть приклади використання.
Відповідь: Звичайне VIEW не зберігає дані фізично, а виконує визначений SQL-запит кожного разу при зверненні, тому дані актуальні, але складні агрегації можуть працювати довше. MATERIALIZED VIEW зберігає результат запиту фізично і прискорює читання агрегованих даних, але потребує оновлення через REFRESH MATERIALIZED VIEW. VIEW підходить для спрощення регулярних вибірок або обмеження доступу до стовпців, а MATERIALIZED VIEW — для важких звітів та аналітики.

5. Опишіть життєвий цикл тригера. Яка різниця між BEFORE, AFTER та INSTEAD OF тригерами?
Відповідь: Тригер пов'язаний із таблицею чи представленням і викликає тригерну функцію (RETURNS TRIGGER) для кожного рядка (FOR EACH ROW) або оператора (FOR EACH STATEMENT) при події INSERT, UPDATE, DELETE чи TRUNCATE. BEFORE виконується до зміни даних і може змінити NEW або скасувати операцію через RAISE EXCEPTION; AFTER виконується після успішної зміни даних (зручно для логування в audit_log); INSTEAD OF замінює операцію та використовується для представлень.

6. Чому важливо обмежувати права доступу користувачів до бази даних? Які рівні гранулярності підтримує PostgreSQL?
Відповідь: Обмеження прав захищає базу від несанкціонованих або помилкових змін, приховує чутливі дані та розподіляє повноваження за ролями. PostgreSQL підтримує гранулярність на рівнях кластера/ролей, бази даних (CONNECT, CREATE, TEMP), схеми (USAGE, CREATE), таблиць/представлень/послідовностей (SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER), окремих стовпців, функцій/процедур та рядків (Row-Level Security).

7. Поясніть різницю між логічним та фізичним резервним копіюванням. Які переваги та недоліки кожного підходу?
Відповідь: Логічне резервне копіювання (pg_dump) вивантажує схему та дані у вигляді SQL-скрипту або архіву: воно зручне для перенесення та вибіркового відновлення окремих таблиць, але повільніше на великих обсягах і не підтримує відновлення на довільний момент часу. Фізичне резервне копіювання (pg_basebackup та архівування WAL) копіює файли даних на рівні блоків, швидше для великих баз і підтримує point-in-time recovery, але залежить від версії сервера та копіює фізичну структуру кластера.

8. Що таке каскадні тригери? Наведіть приклад ситуації, коли вони необхідні.
Відповідь: Каскадні тригери — це ланцюжок спрацювань, коли зміна в одній таблиці через тригер викликає зміну в іншій таблиці або наступний тригер. Вони необхідні для автоматичної підтримки складної бізнес-логіки та узгодженості даних між пов'язаними таблицями — наприклад, при зміні чи скасуванні тренування або абонемента автоматично оновлювати пов'язані показники/статуси та записувати подію в журнал змін.

9. Як індекси впливають на продуктивність операцій INSERT, UPDATE та DELETE? Чому надмірна індексація може бути шкідливою?
Відповідь: Під час INSERT, UPDATE та DELETE СУБД має підтримувати в актуальному стані відповідні індекси (додавати, оновлювати або позначати записи в індексних структурах). Надмірна кількість індексів уповільнює операції запису й оновлення, збільшує обсяг диску, підвищує навантаження на обслуговування (VACUUM / ANALYZE) і може ускладнювати планування запитів.

10. Опишіть стратегію point-in-time recovery. Які компоненти PostgreSQL необхідні для її реалізації?
Відповідь: Point-in-Time Recovery (PITR) дозволяє відновити базу даних на конкретний момент часу або транзакцію (наприклад, до моменту випадкового видалення чи помилкового оновлення даних). Для реалізації необхідні: базова фізична резервна копія (наприклад, через pg_basebackup), архівування WAL-журналів (wal_level = replica або logical, archive_mode = on, archive_command), а під час відновлення — розгорнута базова копія, архів WAL, налаштований restore_command, параметр цілі відновлення (наприклад, recovery_target_time) та файл recovery.signal у каталозі даних.