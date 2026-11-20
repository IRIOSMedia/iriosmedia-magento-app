# The Hyvä store view

This page is for whoever wants to understand or change the second store view of this store, the one with the Hyvä
theme: why it is there, how `bin/setup.sh` creates it, where Hyvä comes from, and how to change themes.

## Why two store views

Most Magento stores use one of two kinds of theme:

- **Luma** and the themes built on it: Magento's standard theme, with RequireJS and Knockout.
- **Hyvä** and the themes built on it: a lighter theme with Alpine.js and Tailwind CSS, popular for its speed.

The IRIOS Media module works with both, but each theme builds its pages differently. Having both in the same store,
each at its own domain, lets you check the module on both side by side, with the same catalog: the events, the
Sponsored Products in the search results, the banners and push notifications.

| | Luma store view | Hyvä store view |
|---|---|---|
| Domain | `LUMA_DOMAIN` | `HYVA_DOMAIN` |
| Website / store view code | `base` / `default` | `hyva` / `hyva` (`HYVA_STORE_CODE`) |
| Theme | Magento Luma | Hyvä Default (`Hyva/default`) |
| Admin | `https://<LUMA_DOMAIN>/<ADMIN_PATH>` | The same admin |

## How the setup creates it

When `HYVA_SOURCE` in `.env` is `github` or `packagist`, `bin/setup.sh`:

1. Installs Hyvä's default theme with Composer (`hyva-themes/magento2-default-theme`), with the modules it needs.
2. Creates a **website**, a **store** and a **store view**, all with the code `hyva`
   (`docker/magento/create-hyva-store.php`). It saves them the same way the admin does, so Magento also creates
   what a new store view needs, such as its order numbers and its product and category URLs.
3. Shares the catalog with the Luma website: the same root category, every product of the Luma website, and the same
   stock.
4. Sets the website's addresses (base URLs) to `https://<HYVA_DOMAIN>/`.
5. Assigns the Hyvä theme to the store view, and sets the checkout to use Magento's Luma checkout (Hyvä's theme
   fallback), which is how Hyvä's default theme works.
6. Deploys the Hyvä static files along with the others.

nginx then runs the Hyvä store view for every request to `HYVA_DOMAIN` (`docker/nginx/default.conf.template`), and
the Luma one for the Luma domain.

Each step checks what exists, so running the setup again changes nothing that is already in place.

**Why a separate website.** IRIOS Media connects one IRIOS Media store per store view, and some of the data the sync
service reads is per website (registered customers, consent withdrawals). A website of its own keeps the two IRIOS
Media stores apart, as two separate retailers would be.

**Products added later.** A product belongs to the websites ticked in its **Product in Websites** section. When you
create a product in the admin, tick both **Main Website** and **Hyvä** so it appears in both store views. To add every
product you created later at once: **Catalog → Products** → tick the products (or **Select All**) → **Actions →
Update attributes** → **Websites** tab → under **Add Product To Websites**, tick **Hyvä** → **Save**. Magento then
creates their addresses (URL rewrites) in the Hyvä store view too.

## Where Hyvä comes from

Hyvä's theme is free and open source (OSL-3.0 / AFL-3.0). Choose where Composer downloads it from with `HYVA_SOURCE`
in `.env`.

**Option 1: `github`** (the default). Hyvä's public GitHub repositories. It needs no key and no account.

**Option 2: `packagist`**. Hyvä's own Composer repository, which is faster to install from and is what Hyvä
recommends for real stores. It needs a free key:

1. Create an account at https://hyva.io, or sign in.
2. In your account, create a free license key for the theme. Hyvä shows two values: the **key** and your **project
   name** (it appears in a repository address like `https://hyva-themes.repo.packagist.com/<project name>/`).
3. Put the key in `auth.json`, under `hyva-themes.repo.packagist.com`, as the `password` (the `username` stays
   `token`):

   ```json
   "hyva-themes.repo.packagist.com": {
     "username": "token",
     "password": "<your Hyvä key>"
   }
   ```

4. In `.env`, set:

   ```dotenv
   HYVA_SOURCE=packagist
   HYVA_PROJECT=<your project name>
   ```

5. Run `bin/setup.sh`.

**Option 3: `none`**. No Hyvä store view: only the Luma one. `HYVA_DOMAIN` can then stay empty.

## Switching themes

You can assign any installed theme to either store view:

1. **Content → Design → Configuration**.
2. Click **Edit** on the row of the store view (for example **Hyvä** under the Hyvä website).
3. **Applied Theme**: choose the theme, for example **Hyvä Default** or **Magento Luma**.
4. **Save Configuration**, then flush the cache: `bin/magento cache:flush`.

In production mode, a theme only works once its static files are deployed. `bin/setup.sh` deploys every installed
theme, so after you install a new theme with Composer, run it again.

To use your own Hyvä child theme, install it (Composer, or in `app/design/frontend/<Vendor>/<theme>`), run
`bin/setup.sh` so it is registered and deployed, and assign it as above.

## Notes

- **Styles.** Hyvä's default theme comes with its CSS already built, so it needs no Node.js on the server. If you
  change Tailwind classes in a child theme, build its CSS (`npm run build` in the theme's `web/tailwind` folder)
  before deploying.
- **Checkout.** Hyvä's default theme sends shoppers to Magento's Luma checkout for the checkout steps. The
  shopper's cart, consent and the IRIOS Media checkout events carry over as usual.
- **Updates.** `bin/update.sh hyva` updates Hyvä to its latest compatible version.
- **IRIOS Media on Hyvä.** See [the Hyvä notes](irios-media.md#10-hyvä-notes) of the IRIOS Media guide: how the ads
  look, and what to do if the module cannot find where to place them.
