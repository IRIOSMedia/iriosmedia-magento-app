<?php
/**
 * Creates the Hyvä website, store and store view, the same way the admin does (Stores → All Stores), so that Magento
 * also creates what a new store view needs: order number sequences and URL rewrites. Safe to run again: whatever
 * exists already is left as it is.
 *
 * Run by bin/setup.sh inside the php container, from the Magento root:
 *   php create-hyva-store.php <code> <name>
 *
 * The new website shares the catalog of the default one: the same root category and every product of the default
 * website, and the same stock (MSI). Products created later must be assigned to both websites (see docs/hyva.md).
 */
declare(strict_types=1);

use Magento\Framework\App\Area;
use Magento\Framework\App\Bootstrap;
use Magento\Framework\App\ResourceConnection;
use Magento\Framework\App\State;
use Magento\Store\Model\GroupFactory;
use Magento\Store\Model\ResourceModel\Group as GroupResource;
use Magento\Store\Model\ResourceModel\Store as StoreResource;
use Magento\Store\Model\ResourceModel\Website as WebsiteResource;
use Magento\Store\Model\StoreFactory;
use Magento\Store\Model\StoreManagerInterface;
use Magento\Store\Model\WebsiteFactory;

[$script, $code, $name] = $argv + [null, 'hyva', 'Hyvä'];
if (!preg_match('/^[a-z][a-z0-9_]{0,31}$/', (string) $code)) {
    fwrite(STDERR, "Invalid store code: use lowercase letters, digits and _, starting with a letter\n");
    exit(1);
}

require getcwd() . '/app/bootstrap.php';
$objects = Bootstrap::create(BP, $_SERVER)->getObjectManager();
$objects->get(State::class)->setAreaCode(Area::AREA_ADMINHTML);

$storeManager = $objects->get(StoreManagerInterface::class);
$db = $objects->get(ResourceConnection::class)->getConnection();
$table = static fn(string $name): string => $objects->get(ResourceConnection::class)->getTableName($name);

$default = $storeManager->getDefaultStoreView();
$defaultWebsite = $storeManager->getWebsite($default->getWebsiteId());
$defaultGroup = $storeManager->getGroup($default->getStoreGroupId());

// 1. Website
$website = $objects->get(WebsiteFactory::class)->create()->load($code, 'code');
if (!$website->getId()) {
    $website->setCode($code)->setName($name)->setSortOrder(10);
    $objects->get(WebsiteResource::class)->save($website);
    echo "Website '$code' created\n";
}
$websiteId = (int) $website->getId();

// 2. Products and stock: the same as the default website. Done before the store view, so that saving the store view
//    creates the URL rewrites of these products.
$db->query(
    sprintf(
        'INSERT IGNORE INTO %s (product_id, website_id) SELECT product_id, ? FROM %s WHERE website_id = ?',
        $table('catalog_product_website'),
        $table('catalog_product_website')
    ),
    [$websiteId, (int) $defaultWebsite->getId()]
);
$channels = $table('inventory_stock_sales_channel');
if ($db->isTableExists($channels)) {
    $stockId = $db->fetchOne(
        "SELECT stock_id FROM $channels WHERE type = 'website' AND code = ?",
        [$defaultWebsite->getCode()]
    );
    if ($stockId) {
        $db->insertOnDuplicate($channels, ['type' => 'website', 'code' => $code, 'stock_id' => (int) $stockId]);
    }
}

// 3. Store (group), with the default root category
$group = $objects->get(GroupFactory::class)->create()->load($code . '_store', 'code');
if (!$group->getId()) {
    $group->setCode($code . '_store')
        ->setName($name . ' Store')
        ->setWebsiteId($websiteId)
        ->setRootCategoryId((int) $defaultGroup->getRootCategoryId());
    $objects->get(GroupResource::class)->save($group);
    echo "Store '{$code}_store' created\n";
}

// 4. Store view
$store = $objects->get(StoreFactory::class)->create()->load($code, 'code');
if (!$store->getId()) {
    $store->setCode($code)
        ->setName($name)
        ->setWebsiteId($websiteId)
        ->setGroupId((int) $group->getId())
        ->setSortOrder(10)
        ->setIsActive(1);
    $objects->get(StoreResource::class)->save($store);
    echo "Store view '$code' created\n";
}

// 5. Defaults of the new website and store
if ((int) $group->getDefaultStoreId() !== (int) $store->getId()) {
    $group->setDefaultStoreId((int) $store->getId());
    $objects->get(GroupResource::class)->save($group);
}
if ((int) $website->getDefaultGroupId() !== (int) $group->getId()) {
    $website->setDefaultGroupId((int) $group->getId());
    $objects->get(WebsiteResource::class)->save($website);
}

echo "Hyvä store view ready: website '$code', store view '$code'\n";
