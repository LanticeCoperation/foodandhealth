# migrations

Body Lab 的資料表與 RLS policy，依序編號。

**規則：schema 的唯一正本在這裡，不要只在 Studio 點。** Studio 點出來的東西不會進版控，
NAS 重建或換機時就會缺。

命名：`0001_description.sql`、`0002_...`，只能往後加，不要改已套用過的檔案。

套用：

```bash
cd infra/supabase && docker compose exec -T db psql -U postgres -d postgres < migrations/0001_xxx.sql
```

每個新表都必須 `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` 並寫好 policy。
anon key 會被打包進 App，沒開 RLS 的表等於對外公開。
