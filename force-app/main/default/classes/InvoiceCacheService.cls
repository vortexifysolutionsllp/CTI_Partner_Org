public without sharing class InvoiceCacheService {

    private static final String CACHE_PARTITION =
        'local.InvoiceCache';

    private static final Integer CACHE_TTL =
        3600;

    private static Cache.OrgPartition getPartition() {

        return Cache.Org.getPartition(
            CACHE_PARTITION
        );
    }

    /*
     * ------------------------------------------------------------
     * PAGE KEY
     * ------------------------------------------------------------
     *
     * Example:
     *
     * invoice_<rootJobId>_page_1
     * invoice_<rootJobId>_page_2
     * invoice_<rootJobId>_page_3
     */
private static String buildPageKey(
    String rootJobId,
    Integer pageNumber
) {

    return
        'invoice' +
        rootJobId +
        'page' +
        String.valueOf(pageNumber);
}

    /*
     * ------------------------------------------------------------
     * META KEY
     * ------------------------------------------------------------
     *
     * Stores the overall processing information.
     */
    private static String buildMetaKey(
        String rootJobId
    ) {

        return
            'invoice' +
            rootJobId +
            'meta';
    }

    /*
     * ------------------------------------------------------------
     * STORE PAGE
     * ------------------------------------------------------------
     */
    public static void storePage(
        String rootJobId,
        Integer pageNumber,
        String pageData
    ) {

        getPartition().put(
            buildPageKey(
                rootJobId,
                pageNumber
            ),
            pageData,
            CACHE_TTL
        );
    }

    /*
     * ------------------------------------------------------------
     * GET PAGE
     * ------------------------------------------------------------
     */
    public static String getPage(
        String rootJobId,
        Integer pageNumber
    ) {

        Object value =
            getPartition().get(
                buildPageKey(
                    rootJobId,
                    pageNumber
                )
            );

        return value == null
            ? null
            : String.valueOf(value);
    }

    /*
     * ------------------------------------------------------------
     * STORE META
     * ------------------------------------------------------------
     */
    public static void storeMeta(
        String rootJobId,
        String metaData
    ) {

        getPartition().put(
            buildMetaKey(rootJobId),
            metaData,
            CACHE_TTL
        );
    }

    /*
     * ------------------------------------------------------------
     * GET META
     * ------------------------------------------------------------
     */
    public static String getMeta(
        String rootJobId
    ) {

        Object value =
            getPartition().get(
                buildMetaKey(rootJobId)
            );

        return value == null
            ? null
            : String.valueOf(value);
    }

    /*
     * ------------------------------------------------------------
     * DELETE PAGE
     * ------------------------------------------------------------
     */
    public static void removePage(
        String rootJobId,
        Integer pageNumber
    ) {

        getPartition().remove(
            buildPageKey(
                rootJobId,
                pageNumber
            )
        );
    }

    /*
     * ------------------------------------------------------------
     * DELETE META
     * ------------------------------------------------------------
     */
    public static void removeMeta(
        String rootJobId
    ) {

        getPartition().remove(
            buildMetaKey(rootJobId)
        );
    }
}