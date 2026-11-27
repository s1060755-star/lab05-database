# Звіт з лабораторної роботи 05: Керування БД, оптимізація продуктивності та автоматизація

**Виконала:** Скоп'юк Олександра  
**Група:** ІПЗ-31  
**СУБД:** PostgreSQL 16 (pgAdmin 4, `psql`)  
**База даних та схема:** `postgres`, схема `public`  
**Каталог проєкту:** `C:\Users\Олександра\Desktop\SportsClub_PG16`  
**Репозиторій:** `https://github.com/s1060755-star/lab05-database.git`

---

## 1. Результати аналізу продуктивності до та після оптимізації

Для оцінки продуктивності виконання SQL-запитів у середовищі PostgreSQL 16 використовувалися команди аналізу планів виконання `EXPLAIN` та `EXPLAIN (ANALYZE, BUFFERS)`. Усі тестові операції модифікації даних виконувалися в межах явних транзакцій із подальшим відкатом (`BEGIN; ... ROLLBACK;`), щоб уникнути небажаних змін стану бази даних.

- **До оптимізації:** за відсутності цільових індексів або при виконанні запитів із неселективними умовами планувальник обирав послідовне сканування таблиць (`Sequential Scan`). Це супроводжувалося вищою оціночною вартістю (`cost`), більшим реальним часом виконання (`actual time`) та підвищеною кількістю звернень до буферного кешу/диску (`BUFFERS`).
- **Після оптимізації:** створення індексів для зовнішніх ключів та умов вибірки (`idx_workouts_member_id`, `idx_workouts_trainer_id`), застосування часткових індексів (`CREATE INDEX ... WHERE ...`), оновлення статистики планувальника (`ANALYZE`) і перебудова індексів (`REINDEX`) дозволили оптимізатору перейти на індексні стратегії (`Index Scan`, `Index Only Scan`, `Bitmap Index Scan`), скоротивши обсяг оброблюваних сторінок.
- **Підтверджені зведені метрики проєкту (`03_final_summary.sql`):**
  - Кількість учасників (`members_count`): `2`
  - Кількість тренерів (`trainers_count`): `2`
  - Кількість тренувань (`workouts_count`): `2`
  - Кількість абонементів (`subscriptions_count`): `2`
  - Сумарний активний дохід (`active_revenue`): `3700.00`
  - Час виконання зведеного запиту: `00:00:00.148`

### SQL-команди аналізу продуктивності та перевірки транзакцій

```sql
-- Оновлення статистики планувальника для всіх таблиць схеми public
ANALYZE;

-- Детальний аналіз реального часу виконання та використання буферів
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    w.workout_id,
    w.workout_date,
    w.member_id,
    w.trainer_id
FROM public.workouts w
WHERE w.trainer_id = 1
ORDER BY w.workout_date DESC;

-- Безпечна перевірка зміни даних у транзакції з обов'язковим відкатом
BEGIN;
UPDATE public.subscriptions
SET price = 1750.00
WHERE member_id = 1;

SELECT subscription_id, member_id, plan_name, price
FROM public.subscriptions
ORDER BY member_id;

ROLLBACK;

SELECT subscription_id, member_id, plan_name, price
FROM public.subscriptions
ORDER BY member_id;
```

---

## 2. Опис створених індексів з обґрунтуванням їх необхідності

У PostgreSQL зовнішні ключі (`FOREIGN KEY`) не індексуються автоматично під час створення таблиць. Через це з'єднання таблиць (`JOIN`), фільтрація (`WHERE`) та групування (`GROUP BY`) за ідентифікаторами клієнтів і тренерів можуть потребувати додаткових сканувань.

- **`idx_workouts_member_id` (`workouts(member_id)`)** — прискорює вибірку тренувань конкретного учасника, з'єднання `workouts` із `members` та `subscriptions`, а також підрахунок кількості тренувань на клієнта.
- **`idx_workouts_trainer_id` (`workouts(trainer_id)`)** — прискорює фільтрацію тренувань за тренером, побудову звітності по тренерах (`trainer_summary`) та операції з'єднання з `trainers`.
- **Первинні ключі (`members_pkey`, `subscriptions_pkey`, `trainers_pkey`, `workouts_pkey`)** — гарантують унікальність ідентифікаторів записів та забезпечують швидкий пошук за первинним ключем.
- **Часткові індекси (`CREATE INDEX ... WHERE ...`)** — індексують лише актуальну або цільову підмножину рядків за незмінним (`IMMUTABLE`) предикатом, зменшуючи розмір індексу на диску та прискорюючи операції запису.

### SQL-команди створення та обслуговування індексів

```sql
-- Індекси для зовнішніх ключів таблиці workouts
CREATE INDEX IF NOT EXISTS idx_workouts_member_id
ON public.workouts (member_id);

CREATE INDEX IF NOT EXISTS idx_workouts_trainer_id
ON public.workouts (trainer_id);

-- Частковий індекс для аналізу абонементів підвищеної вартості (IMMUTABLE-умова)
CREATE INDEX IF NOT EXISTS idx_subscriptions_high_price
ON public.subscriptions (member_id, price)
WHERE price >= 2000;

-- Перебудова індексів таблиці workouts для усунення фрагментації
REINDEX TABLE public.workouts;
```

---

## 3. SQL-код представлень, тригерів та перевірених запитів

У межах лабораторної роботи реалізовано та перевірено аналітичні представлення (`member_summary`, `trainer_summary`), запити з умовною класифікацією (`CASE WHEN`), перевіркою терміну дії абонементів (`s.is_active AND s.valid_until >= CURRENT_DATE`), агрегацією (`GROUP BY ... HAVING`) і систему аудиту змін через тригерну функцію та тригер на таблиці `subscriptions`.

### Представлення, аналітичні запити та аудит через тригери

```sql
-- Представлення аналітики по тренерах
CREATE OR REPLACE VIEW public.trainer_summary AS
SELECT
    t.trainer_id,
    t.full_name AS trainer_name,
    t.specialization,
    COUNT(w.workout_id) AS workouts_count,
    COUNT(DISTINCT w.member_id) AS unique_members_count,
    MIN(w.workout_date) AS first_workout_at,
    MAX(w.workout_date) AS last_workout_at
FROM public.trainers t
LEFT JOIN public.workouts w ON t.trainer_id = w.trainer_id
GROUP BY t.trainer_id, t.full_name, t.specialization
ORDER BY workouts_count DESC, t.trainer_id;

-- Класифікація клієнтів за вартістю абонемента з використанням CASE WHEN
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

-- Перевірка актуальності абонементів станом на поточну дату
SELECT
    s.subscription_id,
    s.member_id,
    s.plan_name,
    s.price,
    s.valid_until,
    s.is_active,
    CASE
        WHEN s.is_active AND s.valid_until >= CURRENT_DATE THEN 'Активний'
        ELSE 'Неактивний або прострочений'
    END AS subscription_status
FROM public.subscriptions s
ORDER BY s.subscription_id;

-- Таблиця журналу аудиту змін
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

-- Тригерна функція для фіксації INSERT, UPDATE та DELETE у public.subscriptions
CREATE OR REPLACE FUNCTION public.log_subscription_audit()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_log (table_name, operation, record_id, new_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.subscription_id, to_jsonb(NEW), current_user);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO public.audit_log (table_name, operation, record_id, old_values, new_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, NEW.subscription_id, to_jsonb(OLD), to_jsonb(NEW), current_user);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO public.audit_log (table_name, operation, record_id, old_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, OLD.subscription_id, to_jsonb(OLD), current_user);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Створення AFTER-тригера на таблиці subscriptions
DROP TRIGGER IF EXISTS trg_subscription_audit ON public.subscriptions;
CREATE TRIGGER trg_subscription_audit
AFTER INSERT OR UPDATE OR DELETE ON public.subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.log_subscription_audit();
```

---


### Команди налаштування прав та резервного копіювання

```sql
-- Створення ролі/користувача лише для читання аналітичних даних
CREATE USER report_viewer WITH PASSWORD 'secure_password';

GRANT CONNECT ON DATABASE postgres TO report_viewer;
GRANT USAGE ON SCHEMA public TO report_viewer;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO report_viewer;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO report_viewer;

-- Автоматичне надання права SELECT на майбутні таблиці у схемі public
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO report_viewer;
```

```powershell
# Створення резервних копій бази даних postgres
pg_dump -U postgres -d postgres -F c -f "C:\Users\Олександра\Desktop\SportsClub_PG16\backup_sportsclub.dump"
pg_dump -U postgres -d postgres -f "C:\Users\Олександра\Desktop\SportsClub_PG16\backup_sportsclub.sql"

# Перевірка відновлення у тестову базу даних
createdb -U postgres test_restore
pg_restore -U postgres -d test_restore "C:\Users\Олександра\Desktop\SportsClub_PG16\backup_sportsclub.dump"
```

---

## 6. Висновки та рекомендації

- Під час виконання лабораторної роботи №5 практично опрацьовано адміністрування та оптимізацію бази даних у PostgreSQL 16 за допомогою pgAdmin 4 і `psql`, створено аналітичні представлення, індекси, тригер аудиту, налаштовано права доступу та виконано резервне копіювання.
- Підтверджено, що поєднання індексації зовнішніх ключів, актуальної статистики `ANALYZE`, безпечних транзакцій (`BEGIN` / `ROLLBACK`) та представлень підвищує швидкість і надійність роботи з даними.
- **Рекомендації:** регулярно оновлювати статистику планувальника (`ANALYZE`), відстежувати невикористовувані або надлишкові індекси, дотримуватися принципу найменших привілеїв при видачі прав і періодично тестувати відновлення даних із резервних копій.

---

## 7. Відповіді на контрольні запитання

### 1. Поясніть різницю між EXPLAIN та EXPLAIN ANALYZE. Коли краще використовувати кожну з цих команд?
**Відповідь:** `EXPLAIN` формує та показує оціночний план виконання запиту на основі статистики без його фактичного запуску. `EXPLAIN ANALYZE` реально виконує запит і додає фактичні метрики (`actual time`, реальну кількість рядків та ітерацій). `EXPLAIN` доцільно застосовувати для швидкої перевірки обраного плану без запуску важкого чи модифікуючого запиту, а `EXPLAIN ANALYZE` (разом із `BUFFERS`) — для вимірювання реального часу виконання та аналізу вузьких місць (при цьому запити зміни даних варто виконувати всередині `BEGIN; ... ROLLBACK;`).

### 2. Які типи індексів підтримує PostgreSQL? Опишіть ситуації, коли доцільно використовувати кожен тип.
**Відповідь:** PostgreSQL підтримує:
- `B-tree` — стандартний індекс загального призначення для операторів `=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `IN`, `ORDER BY` та префіксних шаблонів;
- `Hash` — для швидких перевірок на рівність (`=`);
- `GiST` — для геометричних/просторових об'єктів, діапазонів значень та повнотекстового пошуку;
- `SP-GiST` — для незбалансованих структур даних (наприклад, префіксних або просторових дерев);
- `GIN` — для багатозначних типів (`JSONB`, масиви, повнотекстовий пошук);
- `BRIN` — для надвеликих таблиць, де значення фізично впорядковані (наприклад, хронологічні мітки або послідовні ключі).

### 3. Що таке часткові індекси та в яких випадках їх використання дає найбільший виграш у продуктивності?
**Відповідь:** Частковий індекс створюється з умовою `WHERE` та індексує лише ті рядки таблиці, які задовольняють незмінному (`IMMUTABLE`) предикату. Найбільший виграш він дає тоді, коли запити системно звертаються до стабільної або відносно невеликої підмножини рядків (наприклад, активні абонементи чи замовлення вище певної суми): індекс займає менше місця, швидше оновлюється та краще поміщається в кеш.

### 4. Яка різниця між звичайним представленням (VIEW) та матеріалізованим представленням (MATERIALIZED VIEW)? Наведіть приклади використання.
**Відповідь:** Звичайне `VIEW` зберігає лише визначення SQL-запиту і виконує його при кожному зверненні, тому дані завжди актуальні, але складні агрегації можуть працювати довше. `MATERIALIZED VIEW` фізично зберігає результат запиту, що прискорює читання складних звітів, але вимагає явного оновлення через `REFRESH MATERIALIZED VIEW`. Звичайне `VIEW` добре підходить для уніфікації запитів або обмеження доступу до колонок, а `MATERIALIZED VIEW` — для важкої аналітики та звітів.

### 5. Опишіть життєвий цикл тригера. Яка різниця між BEFORE, AFTER та INSTEAD OF тригерами?
**Відповідь:** Тригер прив'язується до таблиці або представлення та викликає тригерну функцію (`RETURNS TRIGGER`) на рівні рядка (`FOR EACH ROW`) або оператора (`FOR EACH STATEMENT`) у відповідь на події `INSERT`, `UPDATE`, `DELETE` чи `TRUNCATE`. `BEFORE` спрацьовує до запису/зміни рядка і може скоригувати `NEW` або перервати операцію через `RAISE EXCEPTION`; `AFTER` виконується після успішної модифікації даних (оптимально для журналу аудиту `audit_log`); `INSTEAD OF` перехоплює та замінює операцію і застосовується для представлень.

### 6. Чому важливо обмежувати права доступу користувачів до бази даних? Які рівні гранулярності підтримує PostgreSQL?
**Відповідь:** Розмежування прав мінімізує ризики випадкового пошкодження даних, несанкціонованого доступу до конфіденційної інформації та зловживань із боку облікових записів додатків чи користувачів. PostgreSQL підтримує гранулярність на рівнях кластера/ролей, бази даних (`CONNECT`, `CREATE`, `TEMP`), схеми (`USAGE`, `CREATE`), таблиць/представлень/послідовностей (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`), окремих стовпців, функцій/процедур та окремих рядків (`Row-Level Security`).

### 7. Поясніть різницю між логічним та фізичним резервним копіюванням. Які переваги та недоліки кожного підходу?
**Відповідь:** Логічне резервне копіювання (`pg_dump`) експортує схему та дані у вигляді SQL-скрипту або архіву: воно гнучке для міграцій між версіями та вибіркового відновлення окремих таблиць, але працює повільніше на великих базах і не підтримує відновлення на довільний момент часу. Фізичне резервне копіювання (`pg_basebackup` разом із WAL-архівом) копіює блоки файлів даних кластера, швидше для великих обсягів і підтримує point-in-time recovery, але залежить від версії сервера та архітектури кластера.

### 8. Що таке каскадні тригери? Наведіть приклад ситуації, коли вони необхідні.
**Відповідь:** Каскадні тригери — це послідовність спрацювань тригерів, коли зміна в одній таблиці через тригер ініціює зміну в іншій таблиці або запускає наступний тригер. Вони доцільні для підтримки складної бізнес-логіки та цілісності пов'язаних сутностей — наприклад, при зміні статусу абонемента чи скасуванні тренування автоматично оновлювати пов'язані лічильники/статуси та записувати подію в журнал аудиту.

### 9. Як індекси впливають на продуктивність операцій INSERT, UPDATE та DELETE? Чому надмірна індексація може бути шкідливою?
**Відповідь:** Під час `INSERT`, `UPDATE` та `DELETE` СУБД повинна оновлювати або позначати відповідні записи в усіх пов'язаних індексах. Надлишкова кількість індексів уповільнює операції запису й оновлення, збільшує споживання дискового простору, підвищує витрати на фонове очищення та аналіз (`VACUUM` / `ANALYZE`) і може ускладнювати вибір оптимального плану запиту.

### 10. Опишіть стратегію point-in-time recovery. Які компоненти PostgreSQL необхідні для її реалізації?
**Відповідь:** Point-in-Time Recovery (PITR) дозволяє відновити стан бази даних на конкретний момент часу або транзакцію (наприклад, безпосередньо перед помилковим `DELETE` або `UPDATE`). Для реалізації PITR потрібні: базова фізична резервна копія (наприклад, створена через `pg_basebackup`), безперервне архівування WAL-журналів (`wal_level = replica` або `logical`, `archive_mode = on`, налаштований `archive_command`), а на етапі відновлення — розгорнута базова копія, архівні WAL-файли, `restore_command`, параметр цільової точки відновлення (наприклад, `recovery_target_time`) та файл `recovery.signal` у каталозі даних.

---

## 4. Скріншоти та опис виконання роботи

1. **Знімок екрана 2026-11-24 163353.png**
   ![Знімок екрана 2026-11-24 163353.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20163353.png)
   *Опис:* Підключення до сервера баз даних PostgreSQL 16 у pgAdmin 4 (Object Explorer), перегляд панелі моніторингу Dashboard (Activity: Server sessions, Transactions per second, Tuples in, Tuples out, Block I/O).

2. **Знімок екрана 2026-11-24 163423.png**
   ![Знімок екрана 2026-11-24 163423.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20163423.png)
   *Опис:* Розгортання вузла Databases (1) та бази даних postgres у pgAdmin 4 із відображенням системних розділів об'єктів (Casts, Catalogs, Event Triggers, Extensions, Foreign Data Wrappers, Languages, Publications, Schemas, Subscriptions) і метрик бази.

3. **Знімок екрана 2026-11-24 163616.png**
   ![Знімок екрана 2026-11-24 163616.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20163616.png)
   *Опис:* Перегляд схеми public у базі даних postgres у pgAdmin 4 (Tables, Views, Functions, Procedures, Sequences, Trigger Functions) разом із фіксацією активності сесій та транзакцій на вкладці Dashboard.

4. **Знімок екрана 2026-11-24 163753.png**
   ![Знімок екрана 2026-11-24 163753.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20163753.png)
   *Опис:* Моніторинг роботи схеми public та бази даних postgres у pgAdmin 4 (Database sessions, Transactions per second, Tuples out, Block I/O) під час виконання запитів.

5. **Знімок екрана 2026-11-24 164537.png**
   ![Знімок екрана 2026-11-24 164537.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20164537.png)
   *Опис:* Відкрите вікно Query Tool (postgres/postgres@PostgreSQL 16) із підготовленим SQL-запитом створення тестової таблиці CREATE TABLE test_check (id SERIAL PRIMARY KEY, name TEXT NOT NULL);

6. **Знімок екрана 2026-11-24 164622.png**
   ![Знімок екрана 2026-11-24 164622.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20164622.png)
   *Опис:* Успішне виконання запиту створення тестової таблиці test_check у pgAdmin 4 (Query returned successfully in 436 msec., статус CREATE TABLE на вкладці Messages).

7. **Знімок екрана 2026-11-24 164706.png**
   ![Знімок екрана 2026-11-24 164706.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20164706.png)
   *Опис:* Виконання запиту видалення тестової таблиці DROP TABLE IF EXISTS test_check; (Query returned successfully in 91 msec., статус DROP TABLE) для очищення бази даних після перевірки.

8. **Знімок екрана 2026-11-24 164935.png**
   ![Знімок екрана 2026-11-24 164935.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20164935.png)
   *Опис:* Створення таблиці workouts із зовнішніми ключами на trainers та members і вставка тестових даних INSERT INTO members, trainers, workouts (INSERT 0 2, Query returned successfully in 114 msec.).

9. **Знімок екрана 2026-11-24 165054.png**
   ![Знімок екрана 2026-11-24 165054.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20165054.png)
   *Опис:* Перевірка вмісту таблиці workouts запитом SELECT * FROM workouts; у Data Output (Ранковий стретчинг, Базове силове тренуван..., 2026-11-25 09:00:00 та 2026-11-25 18:30:00).

10. **Знімок екрана 2026-11-24 165148.png**
   ![Знімок екрана 2026-11-24 165148.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20165148.png)
   *Опис:* Виконання об'єднувального SQL-запиту JOIN між таблицями workouts w, members m та trainers t (w.member_id = m.member_id, w.trainer_id = t.trainer_id) із виведенням учасників, тренерів та спеціалізацій.

11. **Знімок екрана 2026-11-24 170454.png**
   ![Знімок екрана 2026-11-24 170454.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20170454.png)
   *Опис:* Підготовлений у Query Tool транзакційний SQL-скрипт (BEGIN; UPDATE subscriptions SET price = 1750.00 WHERE member_id = 1; SELECT ...; ROLLBACK; SELECT ...;) для перевірки відкату змін у таблиці subscriptions та поточні рядки у Data Output (1500.00 і 2200.00).

12. **Знімок екрана 2026-11-24 170732.png**
   ![Знімок екрана 2026-11-24 170732.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20170732.png)
   *Опис:* Результат виконання транзакційного скрипта BEGIN ... UPDATE subscriptions ... ROLLBACK у pgAdmin 4 (Successfully run. Total query runtime: 183 msec. 2 rows affected.) зі збереженням початкових цін абонементів.

13. **Знімок екрана 2026-11-24 170831.png**
   ![Знімок екрана 2026-11-24 170831.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20170831.png)
   *Опис:* Виконання запиту з групуванням GROUP BY та умовою HAVING COUNT(*) >= 1 AND workouts_count >= 1 по представленню public.member_summary із виведенням учасників, планів, вартості та кількості тренувань.

14. **Знімок екрана 2026-11-24 170923.png**
   ![Знімок екрана 2026-11-24 170923.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20170923.png)
   *Опис:* Створення індексів idx_workouts_member_id та idx_workouts_trainer_id (CREATE INDEX IF NOT EXISTS) і виконання LEFT JOIN між members та subscriptions із CASE-виразом статусу абонемента (subscription_status = 'Активний').

15. **Знімок екрана 2026-11-24 171105.png**
   ![Знімок екрана 2026-11-24 171105.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20171105.png)
   *Опис:* Створення або оновлення представлення CREATE OR REPLACE VIEW public.trainer_summary з агрегатами COUNT(w.workout_id), COUNT(DISTINCT w.member_id), MIN(w.workout_date), MAX(w.workout_date) та LEFT JOIN із workouts.

16. **Знімок екрана 2026-11-24 171145.png**
   ![Знімок екрана 2026-11-24 171145.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20171145.png)
   *Опис:* Перегляд визначення представлення public.trainer_summary і результатів вибірки в Data Output у pgAdmin 4 (Олена Коваль, Максим Шевчен..., true, 1500.00, 2200.00, workouts_count = 1).

17. **Знімок екрана 2026-11-24 171156.png**
   ![Знімок екрана 2026-11-24 171156.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20171156.png)
   *Опис:* Підтвердження успішного виконання SQL-скрипта зі створення public.trainer_summary та вибірок по представленнях у pgAdmin 4 (Successfully run. Total query runtime: 308 msec. 2 rows affected.).

18. **Знімок екрана 2026-11-24 171331.png**
   ![Знімок екрана 2026-11-24 171331.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20171331.png)
   *Опис:* Запити до системних каталогів information_schema.tables та pg_indexes (WHERE schemaname = 'public' AND tablename = 'workouts') із виведенням індексів таблиці workouts у Data Output.

19. **Знімок екрана 2026-11-24 171447.png**
   ![Знімок екрана 2026-11-24 171447.png](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20171447.png)
   *Опис:* Зведений аналітичний запит зі скалярними підзапитами для підрахунку кількості учасників (2), тренерів (2), тренувань (2), абонементів (2) і доходу за активними абонементами (active_revenue = 3700.00).

20. **Знімок екрана 2026-11-24 171551.jpg**
   ![Знімок екрана 2026-11-24 171551.jpg](final_shots/%D0%97%D0%BD%D1%96%D0%BC%D0%BE%D0%BA%20%D0%B5%D0%BA%D1%80%D0%B0%D0%BD%D0%B0%202026-11-24%20171551.jpg)
   *Опис:* Загальний вигляд вікна pgAdmin 4 після виконання зведеного аналітичного запиту (Total rows: 1, Query complete 00:00:00.148, active_revenue = 3700.00) та розгорнутих таблиць у схемі public.
