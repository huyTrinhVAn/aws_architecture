# Budget Tracker API — local development

Commands below are PowerShell (your default shell on Windows). A note on `curl`: PowerShell aliases `curl` to `Invoke-WebRequest`, which does **not** accept the same flags as real curl — commands below use `curl.exe` explicitly to bypass that alias and get the real curl.exe that ships with Windows.

## Run it

**1. Start a local MySQL database (Docker):**
```powershell
docker run -d --name budget-tracker-db `
  -e MYSQL_ROOT_PASSWORD=devpassword `
  -e MYSQL_DATABASE=budget_tracker `
  -p 3306:3306 `
  mysql:8
```
Wait ~15-30s for it to finish initializing, then check it's ready:
```powershell
docker exec budget-tracker-db mysqladmin ping -h 127.0.0.1 -uroot -pdevpassword --silent
```

If the container already exists from a previous run, just start it again instead of `docker run`:
```powershell
docker start budget-tracker-db
```

**2. Load the schema (only needed once, or after `docker rm`-ing the container):**
```powershell
Get-Content schema.sql | docker exec -i budget-tracker-db mysql -uroot -pdevpassword budget_tracker
```

**3. Install dependencies (first time only):**
```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

**4. Run the app**, with the DB connection passed as environment variables (these match what `app.py` reads via `os.environ`). In PowerShell, each variable is set with `$env:NAME = "value"` on its own line — unlike bash, they can't go on the same line as the command:
```powershell
$env:DB_HOST = "127.0.0.1"
$env:DB_PORT = "3306"
$env:DB_USER = "root"
$env:DB_PASSWORD = "devpassword"
$env:DB_NAME = "budget_tracker"
$env:APP_PORT = "8080"
.\.venv\Scripts\python.exe app.py
```
The app listens on `http://127.0.0.1:8080`. `RECEIPTS_BUCKET` is optional locally — without it, `POST /expenses/:id/receipt` returns a `500` explaining it's not configured (expected until Phase 5 creates the real S3 bucket).

## Endpoints

| Method | Path | Body / Query | Purpose |
|---|---|---|---|
| GET | `/health` | — | health check (used by the ALB later) |
| POST | `/expenses` | JSON `{amount, category_id, note}` | create an expense |
| GET | `/expenses` | query: `category_id`, `from`, `to` (all optional) | list/filter expenses |
| GET | `/expenses/summary` | — | totals grouped by category and by month |
| POST | `/expenses/:id/receipt` | multipart form, field `file` | upload a receipt, stores the S3 key on the expense |

**Try them with curl** (run each in a new PowerShell window/tab so the app keeps running in the first one):
```powershell
curl.exe http://127.0.0.1:8080/health

curl.exe -X POST http://127.0.0.1:8080/expenses -H "Content-Type: application/json" -d '{\"amount\": 25.50, \"category_id\": 1, \"note\": \"Lunch\"}'

curl.exe http://127.0.0.1:8080/expenses
curl.exe "http://127.0.0.1:8080/expenses?category_id=1"
curl.exe http://127.0.0.1:8080/expenses/summary

curl.exe -X POST http://127.0.0.1:8080/expenses/1/receipt -F "file=@C:\path\to\receipt.jpg"
```
Note the `\"` escaping in the `-d` JSON body — PowerShell's double quotes need escaping differently than bash's single-quoted strings did.

Category IDs seeded by `schema.sql`: `1=Food, 2=Transport, 3=Rent, 4=Entertainment, 5=Other`.

## Access the database directly

Open a MySQL shell inside the running container:
```powershell
docker exec -it budget-tracker-db mysql -uroot -pdevpassword budget_tracker
```
Then, at the `mysql>` prompt:
```sql
SHOW TABLES;
SELECT * FROM categories;
SELECT * FROM expenses;
```

To inspect it with a GUI instead (DBeaver, TablePlus, MySQL Workbench...), connect with:
- Host: `127.0.0.1`, Port: `3306`, User: `root`, Password: `devpassword`, Database: `budget_tracker`

## Stop / clean up

```powershell
docker stop budget-tracker-db      # stop, keep data (docker start to resume later)
docker rm -f budget-tracker-db     # remove entirely, including data — re-run schema.sql next time
```
