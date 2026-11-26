# Connecting the store to IRIOS Media

This guide is for whoever connects the store to IRIOS Media once it is running: it covers what you get from IRIOS
Media, the settings of each store view, consent, access for the IRIOS Media sync service, push notifications and a
final checklist. It follows the order in which you do things.

The module is already installed and enabled by `bin/setup.sh`. Until you fill in its settings, it changes nothing on
the storefront. Its own documentation, with every detail, is the
[IRIOS Media module README](https://github.com/IRIOSMedia/iriosmedia-magento-module#readme); this guide applies it to
this store, with its two store views.

In the examples, the Luma store view is at `shop.example.com` (store view code `default`) and the Hyvä one at
`hyva.shop.example.com` (store view code `hyva`). Use your own domains.

## Contents

1. [What IRIOS Media gives you](#1-what-irios-media-gives-you)
2. [How the settings are organised](#2-how-the-settings-are-organised)
3. [General](#3-general)
4. [Consent](#4-consent)
5. [Sponsored Products](#5-sponsored-products)
6. [Display (Image and Video)](#6-display-image-and-video)
7. [Push Notifications](#7-push-notifications)
8. [Access for the IRIOS Media sync service](#8-access-for-the-irios-media-sync-service)
9. [Verify that everything works](#9-verify-that-everything-works)
10. [Hyvä notes](#10-hyvä-notes)

## 1. What IRIOS Media gives you

IRIOS Media creates one *IRIOS Media store* for each store view you connect. Here, that usually means two: one for
Luma and one for Hyvä. For each one, IRIOS Media gives you:

- the **IRIOS Media domain**, for example `yourstore.iriosmedia.online`;
- the **Store ID**, a number;
- the **ad units** you will use, each one with an **ad unit ID** and an **auth**. An ad unit is a space for ads:
  - one or more for **Sponsored Products** (ads among the search results), one per set of positions;
  - one per **Display** placement (a banner with an image or a video);
  - one for **push notifications**.

Keep these values at hand: you type them in the next steps.

## 2. How the settings are organised

The settings are in the admin menu **IRIOS Media**, with four pages: **General**, **Sponsored Products**,
**Display (Image and Video)** and **Push Notifications**. They are also in **Stores → Settings → Configuration**,
under the **IRIOS Media** tab.

**Each store view gets its own values.** At the top left of each page, the **Scope** switcher says which level you
are editing:

1. Choose the store view: **Default Store View** (Luma) or **Hyvä** (under the Hyvä website).
2. Magento asks to confirm the scope change: click **OK**.
3. Next to each setting, untick **Use Website** (or **Use Default**) to give it a value for this store view.
4. Fill in the values, click **Save Config**.
5. Repeat for the other store view, with its own IRIOS Media values.

Two settings exist only in **Default Config**, the same for every store view: **Sensitive categories** and **Tell me
about new versions**.

After you save, flush the cache, because the settings are written into the page HTML:

```bash
bin/magento cache:flush
```

**From the command line.** Every setting can also be saved with `bin/magento config:set`, which is handy to repeat a
setup. For example, the General page of the Hyvä store view:

```bash
bin/magento config:set --scope=stores --scope-code=hyva irios_media/general/enabled 1
bin/magento config:set --scope=stores --scope-code=hyva irios_media/general/js_domain yourstore.iriosmedia.online
bin/magento config:set --scope=stores --scope-code=hyva irios_media/general/store_id 1234
bin/magento cache:flush
```

The [configuration reference](https://github.com/IRIOSMedia/iriosmedia-magento-module#configuration-reference) of the
module lists the path of every setting.

## 3. General

**IRIOS Media → General**, for each store view:

| Setting | Value |
|---|---|
| Enable IRIOS Media | Yes |
| IRIOS Media domain | The domain from IRIOS Media, without `https://`, for example `yourstore.iriosmedia.online` |
| Store ID | The Store ID from IRIOS Media |
| Consent | How the module learns the shopper's consent ([step 4](#4-consent)) |

In **Default Config** you also find:

- **Tell me about new versions**: Yes shows a notice in the admin notifications when a new module version is out.
- **Privacy → Sensitive categories**: only if the store sells health products (pharmacy, medical devices, intimate
  care). Tick those categories; the module then never ties them to a shopper. The sample data has none. The
  [module README](https://github.com/IRIOSMedia/iriosmedia-magento-module#sensitive-categories) explains why and
  what changes.

## 4. Consent

The module only tracks a shopper, and only uses their data for ads, when the shopper agrees. The **Consent** setting
on the General page tells the module where that answer comes from. Choose one option per store view.

**Option 1: Magento cookie restriction notice.** Use it when the store uses Magento's own cookie notice, which is the
simplest for a test store.

1. In **Stores → Settings → Configuration → General → Web → Default Cookie Settings**, set **Cookie Restriction Mode**
   to **Yes** (untick **Use system value** first), and **Save Config**.
2. In **IRIOS Media → General → Consent**, choose **Magento cookie restriction notice**.
3. Flush the cache.

Each new visitor then sees Magento's cookie notice. When they click **Allow Cookies**, the module picks it up on the
same page.

**Option 2: an external consent platform** (Cookiebot, OneTrust, Amasty and similar). Use it when such a platform
already asks for consent.

1. In **IRIOS Media → General → Consent**, choose **External consent platform**.
2. Make the platform call the module when the shopper decides, from its "consent given / changed" callback:

   ```js
   window.IriosMagento.setConsent(true);  // or false, when the shopper declines or withdraws advertising consent
   ```

   `window.IriosMagento` is there from the top of every page, so the platform can call it as early as it likes.

**Option 3: Always.** Only when consent is handled somewhere else and every visitor of this store has agreed.

## 5. Sponsored Products

Sponsored Products are ads for products, shown among the search results and looking like normal results with a
"Sponsored" label.

**IRIOS Media → Sponsored Products**, for each store view:

1. **Enable Sponsored Products**: Yes.
2. **Sponsored label**: leave "Sponsored", or change the text.
3. **Search results positions**: click **Add** once per position where an ad may appear. For each row:
   - **Position**: the place in the results grid, from 1 (the first result) to 50;
   - **Ad unit ID** and **Auth**: from a Sponsored Products ad unit of IRIOS Media.

   One ad unit can fill several positions; for example positions 1 and 5 with the same ad unit.
4. **Save Config**, and flush the cache.

## 6. Display (Image and Video)

Display ads are banners with an image or a video. You create one *placement* for each place where you want a
banner.

**IRIOS Media → Display (Image and Video)**, for each store view:

1. **Enable Display**: Yes.
2. **Placements**: click **Add** once per banner. For each row:
   - **Tag**: a name you choose, with lowercase letters, numbers, `-` and `_`, for example `category-top`;
   - **Format**: Image or Video, the same as the ad unit in IRIOS Media;
   - **Device**: All, Desktop (768 px wide and more) or Mobile;
   - **Ad unit ID** and **Auth**: from IRIOS Media;
   - **Position**: where the banner goes, for example **Category: top**, **Category: in grid** or **Product:
     description**. Choose **Manual only** to place it yourself with the widget (below).
3. **Grid: after product**: for the "Category: in grid" position, after which product the banner goes (6 by
   default).
4. **Save Config**, and flush the cache.

**Placing a banner by hand**, for example on the home page: **Content → Widgets → Add Widget**, type **IRIOS Media
Display**, choose the theme of the store view (Luma or Hyvä), and in **Widget Options** choose the placement's tag
and, on pages like the home page or CMS pages, the **Page type** (for example "Homepage"). Then add the widget to a
page or block in **Layout Updates**.

## 7. Push Notifications

Push notifications let brands send messages to shoppers who agree, through the browser.

**IRIOS Media → Push Notifications**, for each store view:

1. **Enable Push Notifications**: Yes.
2. **Ad unit ID** and **Ad unit auth**: the push ad unit from IRIOS Media.
3. **When to ask for permission**: **After a purchase** (the default), or **After a number of pages** (and the
   number). For testing, "After a number of pages" with 2 pages is quicker.
4. **Ask again after (days)**: 30 by default; 0 asks on every visit, which helps while testing.
5. **Save Config**, and flush the cache.

**The service worker.** The browser needs a small script from the store to receive the notifications: the module
serves it at **`/irios-sw.js`** on each store view's domain. This store's nginx sends that path straight to Magento,
and password protection leaves it open, so it works as it is. Check it on each domain:

```bash
curl -sI https://shop.example.com/irios-sw.js
curl -sI https://hyva.shop.example.com/irios-sw.js
```

Each one should answer `HTTP/2 200` on that same address (no redirect), with `content-type: application/javascript`
and a `service-worker-allowed` header. Before step 1 and 2 are saved for that store view, it answers 404.

**Give IRIOS Media the path `/irios-sw.js` for each store view**, exactly like that, with the leading slash. Without
the slash, browsers look for it next to each page and it fails on every page that is not at the root.

Push notifications need HTTPS with a valid certificate, which this store has on a server. On your computer, trust
Caddy's local authority first ([Quick start](../README.md#quick-start-on-your-computer), option 2).

## 8. Access for the IRIOS Media sync service

The *sync service* is run by IRIOS Media. It reads the catalog, the paid orders and the customers who gave consent
through Magento's REST API, and sends them to IRIOS Media. The module gives it the shoppers' email and phone already
hashed in the store, so they never leave Magento in the clear. To let it in, you create a Magento *integration*: an
access token limited to what you allow.

**1. Allow integration tokens as Bearer tokens.** Since Magento 2.4.4, Magento only accepts an integration token in
the usual `Authorization: Bearer` header when this setting is on:

**Stores → Settings → Configuration → Services → OAuth → Consumer Settings** → **Allow OAuth Access Tokens to be used
as standalone Bearer tokens**: **Yes** (untick **Use system value** first) → **Save Config**.

Or from the command line: `bin/magento config:set oauth/consumer/enable_integration_as_bearer 1`

**2. Create the integration.** In the admin of the Luma domain:

1. **System → Extensions → Integrations** → **Add New Integration**.
2. **Integration Info** tab: **Name** `IRIOS Media`; **Your Password**: your admin password. Leave Email, Callback URL
   and Identity link URL empty.
3. **API** tab: **Resource Access**: **Custom**, and tick only:
   - **IRIOS Media sync API (hashed identifiers)**;
   - **Catalog → Inventory → Products** and **Catalog → Inventory → Categories**;
   - **Catalog → Inventory → Sources** (Magento's inventory, which this store uses);
   - **Stores → Settings → All Stores**;
   - **Stores → Attributes → Product**.

   It needs no access to Sales or Customers: the module's own API gives what the sync service needs.
4. **Save**. In the list, click **Activate** on the IRIOS Media integration, then **Allow**.
5. Magento shows four values. Copy the **Access Token**; the other three are not needed. Click **Done**.

**3. Check the token.** Replace the token and the domain:

```bash
curl -s -H "Authorization: Bearer <access token>" \
  "https://shop.example.com/rest/default/V1/irios-media/v1/orders?limit=1"
```

It should answer `[{"data": [...], "next_cursor": ...}]` (an empty `data` list is fine before the first paid order).
"The consumer isn't authorized" means the Bearer setting of step 1 is off or a resource is missing. With password
protection on, this works without the password, because `/rest/*` is left open for the token ([Security
notes](../README.md#security-notes)).

**4. Send IRIOS Media these values, through a secure channel** (a password manager share, for example, rather than a plain
email or chat message):

| What | Value in this store |
|---|---|
| Base URL of each store view | `https://shop.example.com/` and `https://hyva.shop.example.com/` |
| Store view code of each IRIOS Media store | `default` (Luma) and `hyva` (Hyvä) |
| The integration's Access Token | The one from step 2 |
| Service worker path of each store view | `/irios-sw.js` ([step 7](#7-push-notifications)) |
| Password protection user and password | Only if IRIOS Media people need to see the storefront |

The same token works for both store views: the store view code goes in the REST URL
(`/rest/default/V1/...`, `/rest/hyva/V1/...`).

If you delete the integration, the token stops working. If you click **Reauthorize**, Magento issues a new token,
and you need to send it again.

**Product images.** The catalog sent to IRIOS Media points to the product images under the store's `/media/` path,
and IRIOS Media fetches them from there. That is why `/media/*` is open by default even with password protection
on: product photos are public content anyway. To protect them too, remove `/media/*` from `BASIC_AUTH_OPEN_PATHS` in
`.env` and run `docker compose up -d caddy`.

## 9. Verify that everything works

Do this on each store view, in a private browser window (so you start as a new visitor), with the browser's
developer tools open (F12).

1. **The module is on the page.** View the page source: it has `<script type="application/json" id="irios-config">`
   and a script ending in `Irios_Media/js/irios.js` (or `irios.min.js`). If not, the module is disabled, the domain
   or Store ID is empty for that store view, or the cache needs a flush.
2. **Consent.** Accept the cookie notice (or give consent in your platform). In the console,
   `window.IriosMagento` exists.
3. **Tracker and events.** In **Network**, filter by your IRIOS Media domain. After consent, you see the IRIOS Media
   scripts load and the events go out as you browse: a page view on every page, a category view, a search, a product
   view, add to cart. Before consent, no events go out.
4. **Sponsored Products.** Search for something the campaign covers. The ads appear among the results with the
   "Sponsored" label and the ⓘ "About this ad" button. A position with no running campaign shows nothing, which is
   normal.
5. **Display.** Open a category and a product page: the banners appear in their positions. A placement with no ad
   leaves no gap.
6. **Push.** With "After a number of pages" set to 2, browse two pages: the browser asks to allow notifications.
   **Application → Service Workers** shows `/irios-sw.js` registered.
7. **Orders.** Place a test order with consent given: add a product to the cart, check out as a guest with a test
   address, and pay with **Check / Money order** (enabled in a new Magento store). The sync service only reads paid
   orders, so invoice it: **Sales → Orders** → the order → **Invoice** → **Submit Invoice**. Its status becomes
   **Processing**, and the `curl` of [step 8](#8-access-for-the-irios-media-sync-service) now lists it.
8. **Scheduled tasks.** `bin/magento cron:run` runs every minute in the `cron` container. To see the module's jobs:
   `docker compose exec db sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" mariadb -u"$MARIADB_USER" "$MARIADB_DATABASE" -e "SELECT job_code, status, executed_at FROM cron_schedule WHERE job_code LIKE \"irios%\" ORDER BY schedule_id DESC LIMIT 5"'`

The [module's troubleshooting table](https://github.com/IRIOSMedia/iriosmedia-magento-module#verification-and-troubleshooting)
lists what to do when one of these fails.

## 10. Hyvä notes

The module supports Hyvä: its storefront part is a plain script, without the RequireJS or Knockout code that Hyvä
leaves out. On the Hyvä store view, a few things work a little differently:

- **How the ads look** depends on the theme's styles. Check the Sponsored Products and banners on both store views.
- **Finding the parts of the page.** To place ads, the module looks for the product listing, each product in it, the
  toolbar and the sidebar by their CSS classes, Luma's by default. If an ad does not appear on the Hyvä store view
  while it does on Luma, the module could not find its place. You have two options:
  - **Option 1:** tell the module the Hyvä class names in a small module or theme `di.xml`, as the
    [module README](https://github.com/IRIOSMedia/iriosmedia-magento-module#themes-other-than-luma) shows.
  - **Option 2:** for Display, set the placement's position to **Manual only** and place it with the **IRIOS Media
    Display** widget, choosing the Hyvä theme.
- **Live search.** Hyvä's search box suggests search terms, not products, so no ad appears there; this is the same
  on Luma.
- **Checkout.** Hyvä's default theme uses Magento's Luma checkout, so the checkout events and consent behave as on
  the Luma store view.

More about the Hyvä store view itself in [hyva.md](hyva.md).
