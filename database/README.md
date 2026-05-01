# Gymies database (MySQL)

Tabellen hebben het prefix **gymies_**.

| Tabel | Doel |
|-------|------|
| `gymies_users` | Gebruikers (e-mail, wachtwoord-hash, rol klant/trainer) |
| `gymies_trainer_profiles` | Trainerprofiel (bio, specialisatie, tarief) |
| `gymies_bookings` | Boekingen (klant, trainer, datum/tijd, status, betaling) |
| `gymies_sessions` | Sessie-/API-tokens (inlog sessies) |
| `gymies_password_reset_tokens` | Tokens voor "wachtwoord vergeten" |

Wachtwoorden staan als **hash** in `gymies_users.password_hash` (geen aparte `gymies_passwords`-tabel).

## Automatisch uploaden en uitvoeren (aanbevolen)

**Eenmalig:** op de server een credentials-bestand aanmaken (vervang het wachtwoord door het echte):

```bash
ssh gymies 'cat > ~/.gymies_db.env << EOF
DB_NAME=gymies
DB_USER=gymies_user
DB_PASS=JOUW_WACHTWOORD
DB_HOST=127.0.0.1
DB_PORT=3306
EOF
chmod 600 ~/.gymies_db.env'
```

Daarna lokaal (upload + SQL uitvoeren in één keer):

```bash
./scripts/upload_gymies_db.sh
```

Het script kopieert `create_gymies_tables.sql` en `run_gymies_tables.sh` naar de server en voert de SQL daar uit. Credentials worden alleen op de server in `~/.gymies_db.env` gelezen (niet in de repo).

---

## Handmatig uitvoeren op de server

1. SQL-bestand naar de server kopiëren (of al in de repo op de server):

   ```bash
   scp database/create_gymies_tables.sql niyyahpath:~/create_gymies_tables.sql
   ```

2. Inloggen en uitvoeren (vervang `DBNAME` en `DBUSER` door je MySQL-database en -gebruiker):

   ```bash
   ssh niyyahpath
   mysql -u DBUSER -p DBNAME < ~/create_gymies_tables.sql
   ```

   Of met credentials uit Laravel `.env`:

   ```bash
   cd /var/www/gymies.nl/laravel   # of waar .env staat
   source .env 2>/dev/null || true
   mysql -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" < ~/create_gymies_tables.sql
   ```

   (Als `.env` niet te sourcen is, gebruik dan handmatig de waarden van `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`.)

3. Controleren:

   ```bash
   mysql -u DBUSER -p DBNAME -e "SHOW TABLES LIKE 'gymies_%';"
   ```

## Fout: "Plugin 'mysql_native_password' is not loaded"

De MySQL-gebruiker gebruikt het oude auth-plugin. Omzetten naar `caching_sha2_password`:

**Op de server, inloggen als MySQL-root (of andere admin):**

```bash
sudo mysql
```

In de MySQL-shell (vervang `jouw_user` en `jouw_wachtwoord` door je echte DB-user en wachtwoord):

```sql
ALTER USER 'jouw_user'@'localhost' IDENTIFIED WITH caching_sha2_password BY 'jouw_wachtwoord';
FLUSH PRIVILEGES;
EXIT;
```

Daarna opnieuw:

```bash
mysql -u jouw_user -p jouw_database < ~/create_gymies_tables.sql
```

Als je geen `sudo mysql` hebt, gebruik dan het wachtwoord van de root-gebruiker: `mysql -u root -p` en voer daarna dezelfde `ALTER USER` uit.

## Opnieuw aanmaken (let op: wist data)

Het script doet `DROP TABLE IF EXISTS` voor alle TrainMaat-tabellen in de juiste volgorde, daarna `CREATE TABLE`. Alleen opnieuw draaien als je de TrainMaat-data mag wissen.
