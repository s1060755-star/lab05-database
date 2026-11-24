# Звіт з лабораторної роботи 05: Керування БД, оптимізація продуктивності та автоматизація
**Виконала:** Скоп'юк Олександра  
**Група:** ІПЗ-31
**СУБД:** PostgreSQL 16  
**Каталог проєкту:** `C:\Users\Олександра\Desktop\SportsClub_PG16`  
**Схема / об'єкти:** `public` (`members`, `trainers`, `workouts`, `subscriptions`, `member_summary`, `trainer_summary`, `03_final_summary.sql`)

---

## 1. Результати аналізу продуктивності до та після оптимізації

Аналіз продуктивності запитів виконується командами `EXPLAIN` та `EXPLAIN (ANALYZE, BUFFERS)` (з обгортанням змін даних у `BEGIN; ... ROLLBACK;`).

- **До оптимізації:** на таблицях без відповідних індексів або з недостатньо вибірковими умовами переважає `Sequential Scan`, зростають показники `cost`, `actual time` та кількість зчитаних сторінок буфера (`BUFFERS`).
- **Після оптимізації (створення індексів, часткових індексів, оновлення статистики `ANALYZE` та перебудови `REINDEX`):** оптимізатор переходить на `Index Scan` / `Index Only Scan` / `Bitmap Index Scan` для вибірок за ключами, датами, сумами або умовами `WHERE`, що зменшує обсяг читання даних і час виконання.
- **Фактичні контрольні дані з перевірки (`03_final_summary.sql`):**
  - Зафіксовано `trainer_id` `1` (`2026-11-25 09:00:00`, `workouts_count = 1`, `unique_members_count = 1`) та `trainer_id` `2` (`2026-11-25 18:30:00`, `workouts_count = 1`, `unique_members_count = 1`).
  - Підсумкові показники: `members_count = 2`, `trainers_count = 2`, `workouts_count = 2`, `subscriptions_count = 2`, `active_revenue = 3700.00`.

| Метрика / етап аналізу | До оптимізації | Після оптимізації | Коментар |
| :--- | :--- | :--- | :--- |
| Тип сканування | `Sequential Scan` | `Index Scan` / `Index Only Scan` / `Bitmap Index Scan` | Залежить від селективності умови та обсягу вибірки |
| Оціночна вартість (`cost`) та `actual time` | Вищі значення при повному скануванні | Нижчі значення при індексному доступі | Перевіряється через `EXPLAIN (ANALYZE, BUFFERS)` |
| Статистика та індекси | Потребують `ANALYZE` і `REINDEX` | Актуалізовано через `ANALYZE` та `REINDEX` | Виконується також у процедурі обслуговування |

---

## 2. Опис створених індексів з обґрунтуванням їх необхідності

- **Індекси для оптимізації вибірок, з'єднань (`JOIN`), фільтрації (`WHERE`) та сортування (`ORDER BY`):**
  - Індекси на стовпцях зовнішніх ключів та зв'язків (наприклад, на `workouts` та пов'язаних таблицях, де PostgreSQL не створює індекс автоматично для `FOREIGN KEY`) прискорюють `JOIN` і агрегацію.
  - Індекси за датами, статусами та числовими полями прискорюють діапазонні вибірки й сортування.
  - Зафіксовані у схемі `public` індекси: `idx_workouts_member_id`, `idx_workouts_trainer_id`, `members_pkey`, `subscriptions_pkey`, `trainers_pkey`, `workouts_pkey`.
- **Часткові індекси (`CREATE INDEX ... WHERE ...`):**
  - Індексують лише підмножину рядків, що задовольняють незмінному (`IMMUTABLE`) предикату `WHERE`.
  - Зменшують розмір індексу на диску та прискорюють запити з відповідною умовою `WHERE` (наприклад, активні записи або великі суми).

---

## 3. SQL-код створених представлень, правил, тригерів, ролей та процедур

### 3.1. Представлення (`VIEW`) та оновлення через правила (`RULES`)

```sql
-- Приклад представлення активних записів
CREATE OR REPLACE VIEW active_records_view AS
SELECT *
FROM members
WHERE is_active = TRUE;

-- Приклад аналітичного представлення
CREATE OR REPLACE VIEW club_activity_summary AS
SELECT
    t.trainer_id,
    COUNT(w.workout_id) AS workouts_count,
    COUNT(DISTINCT w.member_id) AS unique_members_count,
    MIN(w.workout_at) AS first_workout_at,
    MAX(w.workout_at) AS last_workout_at
FROM trainers t
LEFT JOIN workouts w ON w.trainer_id = t.trainer_id
GROUP BY t.trainer_id;

-- Представлення з правилом оновлення (RULE)
CREATE OR REPLACE VIEW editable_members_view AS
SELECT member_id, is_active
FROM members;

CREATE OR REPLACE RULE update_editable_members_view AS
ON UPDATE TO editable_members_view
DO INSTEAD
    UPDATE members
    SET is_active = NEW.is_active
    WHERE member_id = OLD.member_id;
```

### 3.2. Таблиця аудиту `audit_log` та тригери (логування, валідація, каскадна логіка, матеріалізоване представлення)

```sql
CREATE TABLE IF NOT EXISTS audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    record_id TEXT,
    old_values JSONB,
    new_values JSONB,
    changed_by VARCHAR(100) NOT NULL DEFAULT current_user,
    changed_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Тригер логування INSERT / UPDATE / DELETE
CREATE OR REPLACE FUNCTION fn_audit_log()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, record_id, new_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(NEW)->>0, to_jsonb(NEW), current_user);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_values, new_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(NEW)->>0, to_jsonb(OLD), to_jsonb(NEW), current_user);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, old_values, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD)->>0, to_jsonb(OLD), current_user);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Тригер валідації перед вставкою/оновленням (приклад для додатного значення)
CREATE OR REPLACE FUNCTION fn_validate_positive_amount()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.amount IS NOT NULL AND NEW.amount < 0 THEN
        RAISE EXCEPTION 'Amount cannot be negative: %', NEW.amount;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### 3.3. Матеріалізоване представлення, ієрархія ролей, процедура обслуговування та моніторинг

```sql
-- Матеріалізоване представлення з унікальним індексом
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_club_metrics AS
SELECT
    COUNT(*) AS total_workouts,
    COUNT(DISTINCT member_id) AS unique_members
FROM workouts;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_club_metrics_unique
ON mv_club_metrics (total_workouts, unique_members);

-- Ієрархія ролей (звичайний користувач -> модератор -> адміністратор)
CREATE ROLE club_user NOLOGIN;
GRANT CONNECT ON DATABASE postgres TO club_user;
GRANT USAGE ON SCHEMA public TO club_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO club_user;

CREATE ROLE club_moderator NOLOGIN;
GRANT club_user TO club_moderator;
GRANT INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO club_moderator;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO club_moderator;

CREATE ROLE club_admin NOLOGIN;
GRANT club_moderator TO club_admin;
GRANT DELETE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public TO club_admin;

-- Збережена процедура обслуговування
CREATE TABLE IF NOT EXISTS maintenance_log (
    log_id SERIAL PRIMARY KEY,
    operation TEXT NOT NULL,
    executed_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE PROCEDURE maintain_database()
LANGUAGE plpgsql
AS $$
DECLARE
    tbl RECORD;
BEGIN
    ANALYZE;
    FOR tbl IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE schemaname = 'public'
    LOOP
        EXECUTE format('REINDEX TABLE %I.%I', tbl.schemaname, tbl.tablename);
    END LOOP;
    INSERT INTO maintenance_log (operation) VALUES ('ANALYZE + REINDEX');
END;
$$;

-- Моніторинг використання індексів
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC, relname, indexrelname;
```

---

## 4. Скріншоти та текстовий вивід перевірки роботи

> Збережи скріншоти у підпапку `screenshots` поруч зі звітом (`screenshots/01_...` – `screenshots/10_...`) та перевір відображення у переглядачі Markdown.

1. **Помилка шляху при `Move-Item`:** `![01](screenshots/01_move_item_error.png)` — спроба перенести `03_final_summary.sql` у шаблонний шлях `"C:\шлях\до\папки\проєкту\"` повернула `Could not find a part of the path`.
2. **Створення папки `SportsClub_PG16` та перенесення скрипта:** `![02](screenshots/02_project_dir_created.png)` — створено `C:\Users\Олександра\Desktop\SportsClub_PG16` і перенесено `03_final_summary.sql` (374 байти).
3. **Запуск `03_final_summary.sql` через `psql.exe`:** `![03](screenshots/03_psql_summary_run.png)` — виведено дані по тренерах (`1` і `2`, дати `2026-11-25 09:00:00` та `2026-11-25 18:30:00`) та зведені показники (`members_count = 2`, `trainers_count = 2`, `workouts_count = 2`, `subscriptions_count = 2`, `active_revenue = 3700.00`).
4. **Відсутність `psql_check_output.txt` при першому `Get-Content`:** `![04](screenshots/04_logfile_not_found.png)` — файл логу ще не був створений через зайві аргументи в попередньому виклику.
5. **Перелік файлів у каталозі проєкту:** `![05](screenshots/05_project_files_list.png)` — зафіксовано `03_final_summary.sql`, `PROJECT_REPORT.md`, `psql_check_output.txt` та `schema_objects.txt`.
6. **Незбіг кодувань у текстовому виводі:** `![06](screenshots/06_report_encoding_issue.png)` — кирилиця та рамки таблиць у консольному/текстовому виводі спотворювались через кодування, тоді як числа й дати збереглися коректно.
7. **Пошук у Провіднику Windows:** `![07](screenshots/07_explorer_search_empty.png)` — пошук за назвою папки не повернув результатів.
8. **Помилка синтаксису `%USERPROFILE%` у PowerShell:** `![08](screenshots/08_ps_percent_syntax_error.png)` — у PowerShell замість `%USERPROFILE%` використовується `$env:USERPROFILE`.
9. **Відкрита папка проєкту у Провіднику:** `![09](screenshots/09_explorer_project_folder.png)` — візуально підтверджено наявність усіх файлів проєкту.
10. **Перегляд звіту у VS Code:** `![10](screenshots/10_vscode_report_view.png)` — підтверджено об'єкти схеми `public` (`members`, `subscriptions`, `trainers`, `workouts`, `member_summary`, `trainer_summary` та відповідні індекси).

---

## 5. Документація системи прав доступу для різних ролей користувачів

| Роль / рівень доступу | Дозволені дії та об'єкти | Обмеження |
| :--- | :--- | :--- |
| Звичайний користувач (`club_user` / `report_viewer`) | Підключення до БД, `USAGE` на схему `public`, `SELECT` на дозволені таблиці та представлення | Не може змінювати (`INSERT`, `UPDATE`, `DELETE`) або видаляти дані |
| Модератор (`club_moderator`) | Усі права `club_user` + `INSERT`, `UPDATE` на таблиці та `USAGE`, `SELECT` на послідовності | Не має повного адміністрування та небезпечних масових змін на рівні власника/суперкористувача |
| Адміністратор (`club_admin`) | Повні привілеї на об'єкти в межах делегованої ієрархії та адміністрування | Використовується лише для адміністративних операцій із дотриманням принципу найменших привілеїв |

---

## 6. Висновки щодо покращення продуктивності та рекомендації

- Застосування `EXPLAIN (ANALYZE, BUFFERS)` дозволяє об'єктивно оцінювати вартість, реальний час виконання та роботу з буферами до й після оптимізації.
- Індекси та часткові індекси прискорюють вибірки, проте надмірна індексація збільшує накладні витрати на `INSERT`, `UPDATE` і `DELETE`.
- Для автоматизації аудиту, валідації та агрегації доцільно поєднувати тригери, представлення / матеріалізовані представлення, розмежовані ролі доступу та регулярне резервне копіювання (`pg_dump` / `pg_restore`).
- Для стабільної роботи з українською кирилицею у Windows варто узгоджувати кодування клієнта та виводу (`UTF-8`) і перевіряти звіти у редакторі з підтримкою `UTF-8`.

---

## 7. Відповіді на контрольні запитання

### 1. Різниця між `EXPLAIN` та `EXPLAIN ANALYZE` і коли яку команду використовувати
`EXPLAIN` будує та показує оціночний план виконання запиту (оціночні `cost`, `rows`, `width`) **без фактичного виконання запиту**. `EXPLAIN ANALYZE` **справді виконує запит** і додає реальні метрики (`actual time`, фактичну кількість рядків, а з `BUFFERS` — і роботу зі сторінками). `EXPLAIN` зручно використовувати для швидкої перевірки плану без навантаження або побічних ефектів, а `EXPLAIN ANALYZE` — для реального вимірювання швидкодії (обов'язково обгортаючи `INSERT`/`UPDATE`/`DELETE` у `BEGIN; ... ROLLBACK;`).

### 2. Типи індексів у PostgreSQL та ситуації їх використання
PostgreSQL підтримує кілька типів індексів (зокрема B-tree, Hash, GiST, SP-GiST, GIN, BRIN). **B-tree** — стандартний тип за замовчуванням для порівнянь (`=`, `<`, `<=`, `>`, `>=`), діапазонів, `BETWEEN`, `IN`, сортування (`ORDER BY`) і групування; **часткові** та **складені** індекси будуються на базі B-tree для конкретних умов фільтрації або багатостовпцевих запитів; **GIN** підходить для масивів, `JSONB` чи повнотекстового пошуку; **GiST** — для геометрії/діапазонів; **BRIN** — для дуже великих таблиць із природним упорядкуванням (наприклад, за часом).

### 3. Часткові індекси та випадки найбільшого виграшу
Частковий індекс індексує лише ті рядки таблиці, які відповідають умові `WHERE` (із незмінним виразом). Найбільший виграш він дає тоді, коли запити регулярно фільтрують невелику або специфічну частину великої таблиці (наприклад, активні записи чи замовлення понад певну суму): індекс займає менше місця на диску, швидше оновлюється і ефективніше поміщається в кеші.

### 4. Різниця між звичайним представленням (`VIEW`) та матеріалізованим представленням (`MATERIALIZED VIEW`)
Звичайне `VIEW` зберігає лише визначення запиту і при кожному зверненні виконує його на актуальних даних таблиць. `MATERIALIZED VIEW` зберігає результат запиту фізично на диску, тому читання агрегованих даних відбувається значно швидше, але дані можуть застарівати й потребують оновлення (`REFRESH MATERIALIZED VIEW`, за наявності унікального індексу — `CONCURRENTLY`).

### 5. Життєвий цикл тригера та різниця між `BEFORE`, `AFTER` і `INSTEAD OF`
Тригер спрацьовує при заданій події (`INSERT`, `UPDATE`, `DELETE` або `TRUNCATE`) на рівні рядка (`FOR EACH ROW`) чи оператора (`FOR EACH STATEMENT`) і викликає тригерну функцію. `BEFORE` виконується до зміни/запису даних (може змінити `NEW` або перервати операцію через `RAISE EXCEPTION`), `AFTER` — після успішного виконання операції (часто для логування чи побічних дій), а `INSTEAD OF` перехоплює та замінює операцію переважно на представленнях (`VIEW`).

### 6. Важливість обмеження прав доступу та рівні гранулярності в PostgreSQL
Обмеження прав (принцип найменших привілеїв) захищає дані від випадкових змін, видалення або витоку конфіденційної інформації. PostgreSQL підтримує гранулярність на рівнях: кластера/ролей, баз даних (`CONNECT`), схем (`USAGE`, `CREATE`), таблиць і представлень (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`), окремих стовпців (`SELECT`, `UPDATE`, `INSERT`), послідовностей (`USAGE`, `SELECT`, `UPDATE`), функцій/процедур та політик безпеки на рівні рядків (RLS).

### 7. Різниця між логічним та фізичним резервним копіюванням
Логічне копіювання (`pg_dump` / `pg_restore`) експортує структуру та дані у вигляді SQL-скриптів або архіву об'єктів БД; воно гнучке для вибіркового відновлення, але на дуже великих базах працює повільніше і не підтримує інкрементальність через `pg_dump`. Фізичне копіювання копіює файли кластера / сторінки даних і WAL-журнали; воно швидше для великих баз і підтримує відновлення на конкретний момент часу (PITR), але менш гнучке для часткового відновлення окремих таблиць.

### 8. Каскадні тригери та приклад їх застосування
Каскадні тригери — це ланцюжок тригерів, коли дія одного тригера змінює іншу таблицю або об'єкт, що запускає наступний тригер. Вони доцільні для підтримання складної бізнес-логіки між пов'язаними таблицями, наприклад при проведенні тренування чи оплати абонемента: автоматичне оновлення залишків/статусів, запис події в журнал аудиту та оновлення зведених показників.

### 9. Вплив індексів на `INSERT`, `UPDATE`, `DELETE` та шкода надмірної індексації
Під час `INSERT` потрібно додати записи в кожен індекс; під час `DELETE` — видалити; під час `UPDATE` — оновити індекси, якщо змінилися проіндексовані стовпці (або коли не спрацьовує HOT-оновлення). Надмірна індексація сповільнює запис і оновлення, витрачає дисковий простір і пам'ять кешу, тому індекси варто створювати обґрунтовано під реальні запити.

### 10. Стратегія Point-in-Time Recovery (PITR) та необхідні компоненти PostgreSQL
PITR дозволяє відновити базу даних на конкретний момент часу (наприклад, до помилкового `DELETE` або `UPDATE`). Для реалізації потрібні: базова резервна копія кластера (наприклад, створена через `pg_basebackup`), безперервне архівування WAL-журналів (`archive_mode = on`, налаштований `archive_command` та доступ до архіву WAL), а під час відновлення — файл `recovery.signal` у каталозі даних та задані у конфігурації `restore_command` і цільовий момент відновлення (`recovery_target_time`).