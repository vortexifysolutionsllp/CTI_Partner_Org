import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getBillingDetails
    from '@salesforce/apex/InvoiceGeneratorController.getBillingDetails';

import generateInvoice
    from '@salesforce/apex/InvoiceGeneratorController.generateInvoice';

import getInvoiceStatus
    from '@salesforce/apex/InvoiceGeneratorController.getInvoiceStatus';

import getInvoicePage
    from '@salesforce/apex/InvoiceGeneratorController.getInvoicePage';

import createInvoicePdfPage
    from '@salesforce/apex/InvoiceGeneratorController.createInvoicePdfPage';

import getPdfJobStatus
    from '@salesforce/apex/InvoiceGeneratorController.getPdfJobStatus';

import mergeInvoicePdfs
    from '@salesforce/apex/InvoiceGeneratorController.mergeInvoicePdfs';

import saveMergedInvoice
    from '@salesforce/apex/InvoiceGeneratorController.saveMergedInvoice';

const INVOICE_POLL_INTERVAL_MS = 2000;

/*
 * aPDF allows up to 3 requests/sec.
 * 2 seconds between status requests keeps us well under that.
 */
const PDF_POLL_INTERVAL_MS = 2000;
const PDF_MAX_ATTEMPTS = 60;

export default class InvoiceGenerator extends LightningElement {

    @api recordId;

    @track billingStartDate;
    @track billingEndDate;
    @track jobStatus;
    @track errorMessage;

    isGenerating = false;
    isSaving = false;

    jobId;
    requestKey;
    pollingInterval;

    // Guards against overlapping status calls / duplicate PDF processing
    isCheckingStatus = false;
    retrievalStarted = false;

    /* ------------------------------------------------------------
     * LIFECYCLE
     * ------------------------------------------------------------ */

    connectedCallback() {
        this.loadBillingDetails();
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    /* ------------------------------------------------------------
     * GETTERS
     * ------------------------------------------------------------ */

    get buttonDisabled() {
        return this.isGenerating || this.isSaving;
    }

    /* ------------------------------------------------------------
     * INPUT HANDLERS
     * ------------------------------------------------------------ */

    handleBillingStartDateChange(event) {
        this.billingStartDate = event.target.value;
    }

    handleBillingEndDateChange(event) {
        this.billingEndDate = event.target.value;
    }

    /* ------------------------------------------------------------
     * LOAD DEFAULT BILLING PERIOD
     * ------------------------------------------------------------ */

    async loadBillingDetails() {
        try {
            const result = await getBillingDetails({
                subscriberOrgId: this.recordId
            });

            this.billingStartDate = result.billingStartDate;
            this.billingEndDate = result.billingEndDate;

        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
        }
    }

    /* ------------------------------------------------------------
     * GENERATE INVOICE
     * ------------------------------------------------------------ */

    async handleGenerateInvoice() {

        if (this.isGenerating || this.isSaving) {
            return;
        }

        if (!this.billingStartDate || !this.billingEndDate) {
            this.errorMessage = 'Please select both billing dates.';
            this.showToast('Error', this.errorMessage, 'error');
            return;
        }

        if (this.billingStartDate > this.billingEndDate) {
            this.errorMessage =
                'Billing Start Date cannot be later than Billing End Date.';
            this.showToast('Error', this.errorMessage, 'error');
            return;
        }

        this.isGenerating = true;
        this.errorMessage = null;
        this.jobStatus = 'Starting invoice generation...';
        this.retrievalStarted = false;
        this.isCheckingStatus = false;

        try {
            const result = await generateInvoice({
                subscriberOrgId: this.recordId,
                billingStartDate: this.billingStartDate,
                billingEndDate: this.billingEndDate
            });

            this.jobId = result.jobId;
            this.requestKey = result.requestKey;

            this.jobStatus = 'Invoice generation started.';

            this.startPolling();

        } catch (error) {

            this.isGenerating = false;
            this.errorMessage = this.getErrorMessage(error);
            this.jobStatus = 'Failed';

            this.showToast('Error', this.errorMessage, 'error');
        }
    }

    /* ------------------------------------------------------------
     * POLL TWILIO RETRIEVAL STATUS
     * ------------------------------------------------------------ */

    startPolling() {

        this.stopPolling();

        this.checkInvoiceStatus();

        this.pollingInterval = setInterval(() => {
            this.checkInvoiceStatus();
        }, INVOICE_POLL_INTERVAL_MS);
    }

    stopPolling() {

        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
    }

    async checkInvoiceStatus() {

        // Skip if there's nothing to check, a check is already running,
        // or PDF processing has already begun.
        if (
            !this.requestKey ||
            this.isCheckingStatus ||
            this.retrievalStarted
        ) {
            return;
        }

        this.isCheckingStatus = true;

        try {

            const result = await getInvoiceStatus({
                requestKey: this.requestKey
            });

            // A response can arrive after retrieval already started
            if (this.retrievalStarted) {
                return;
            }

            if (result.status === 'QUEUED') {

                this.jobStatus = 'Invoice generation queued...';

            } else if (result.status === 'PROCESSING') {

                this.jobStatus =
                    'Processing Twilio calls. Pages retrieved: ' +
                    (result.pagesRetrieved || 0);

            } else if (result.status === 'COMPLETED') {

                this.stopPolling();
                this.retrievalStarted = true;

                this.jobStatus = 'Twilio call retrieval completed.';

                await this.retrieveAllPages(result.pagesRetrieved);

            } else if (result.status === 'FAILED') {

                this.stopPolling();
                this.isGenerating = false;

                this.errorMessage =
                    result.errorMessage ||
                    'Invoice generation failed.';

                this.jobStatus = 'Failed';

                this.showToast('Error', this.errorMessage, 'error');

            } else if (result.status === 'EXPIRED') {

                this.stopPolling();
                this.isGenerating = false;

                this.errorMessage =
                    result.errorMessage ||
                    'Invoice processing data expired.';

                this.jobStatus = 'Expired';

                this.showToast('Error', this.errorMessage, 'error');
            }

        } catch (error) {

            this.stopPolling();
            this.isGenerating = false;

            this.errorMessage = this.getErrorMessage(error);
            this.jobStatus = 'Failed';

            this.showToast('Error', this.errorMessage, 'error');

        } finally {

            this.isCheckingStatus = false;
        }
    }

    /* ------------------------------------------------------------
     * BUILD PDF PAGES -> MERGE -> SAVE
     * ------------------------------------------------------------ */

    async retrieveAllPages(totalPages) {

        try {

            this.isSaving = true;

            const total = Number(totalPages) || 0;

            if (total < 1) {
                throw new Error('No invoice pages were retrieved.');
            }

            this.jobStatus = 'Generating invoice pages...';

            const pdfUrls = [];

            for (let pageNumber = 1; pageNumber <= total; pageNumber++) {

                this.jobStatus =
                    `Processing invoice page ${pageNumber} of ${total}...`;

                const pageJson = await getInvoicePage({
                    requestKey: this.requestKey,
                    pageNumber: pageNumber
                });

                const pageData = JSON.parse(pageJson);

                // Cache page -> HTML
                const html = this.createInvoicePageHtml(
                    pageData,
                    pageNumber,
                    total
                );

                // Ask aPDF to create the page PDF
                const pdfJobId = await createInvoicePdfPage({ html: html });

                // Wait for aPDF to finish
                const pdfUrl = await this.waitForPdfJob(pdfJobId);

                pdfUrls.push(pdfUrl);
            }

            // Merge all page PDFs
            this.jobStatus = 'Merging invoice pages...';

            const mergeResult = await mergeInvoicePdfs({
                pdfUrls: pdfUrls
            });

            const mergeData = JSON.parse(mergeResult);

            if (!mergeData.file) {
                throw new Error('aPDF did not return a merged PDF URL.');
            }

            // Save the final PDF into Salesforce Files
            this.jobStatus = 'Saving invoice to Salesforce Files...';

            const contentDocumentId = await saveMergedInvoice({
                subscriberOrgId: this.recordId,
                requestKey: this.requestKey,
                mergedPdfUrl: mergeData.file
            });

            this.jobStatus = 'Invoice saved successfully.';

            this.showToast(
                'Success',
                'Invoice PDF has been saved to Files.',
                'success'
            );

        } catch (error) {

            this.jobStatus = 'Invoice generation failed.';
            this.errorMessage = this.getErrorMessage(error);

            this.showToast('Error', this.errorMessage, 'error');

        } finally {

            this.isSaving = false;
            this.isGenerating = false;
        }
    }

    /* ------------------------------------------------------------
     * WAIT FOR ONE aPDF JOB
     * ------------------------------------------------------------ */

    async waitForPdfJob(pdfJobId) {

        for (let attempt = 1; attempt <= PDF_MAX_ATTEMPTS; attempt++) {

            const response = await getPdfJobStatus({
                jobId: pdfJobId
            });

            const status = JSON.parse(response);

            const state = (status.status || '').toLowerCase();

            if (['completed', 'successful', 'success'].includes(state)) {

                if (!status.result || !status.result.file) {
                    throw new Error(
                        'aPDF job completed without a PDF URL.'
                    );
                }

                return status.result.file;
            }

            if (['failed', 'error'].includes(state)) {

                throw new Error(
                    status.error || 'aPDF PDF generation failed.'
                );
            }

            // Any other state (pending / processing): keep waiting
            await this.sleep(PDF_POLL_INTERVAL_MS);
        }

        throw new Error('aPDF PDF generation timed out.');
    }

    sleep(milliseconds) {
        return new Promise(resolve => setTimeout(resolve, milliseconds));
    }

    /* ------------------------------------------------------------
     * HTML FOR ONE INVOICE PAGE
     * ------------------------------------------------------------ */

    createInvoicePageHtml(pageData, pageNumber, totalPages) {

        const calls = pageData.calls || [];

        const rows = calls.map(call => {

            return `
                <tr>
                    <td>${this.escapeHtml(call.fromNumber)}</td>
                    <td>${this.escapeHtml(call.toNumber)}</td>
                    <td>${this.escapeHtml(call.duration)}</td>
                    <td>${this.escapeHtml(call.direction)}</td>
                    <td>${this.escapeHtml(call.price)}</td>
                    <td>${this.escapeHtml(call.priceUnit)}</td>
                    <td>${this.escapeHtml(this.formatDateTime(call.startTime))}</td>
                    <td>${this.escapeHtml(this.formatDateTime(call.endTime))}</td>
                </tr>
            `;
        }).join('');

        return `
<!DOCTYPE html>
<html>
<head>

<meta charset="UTF-8">

<style>

@page {
    size: A4 landscape;
    margin: 8mm;
}

body {
    font-family: Arial, sans-serif;
    font-size: 8px;
    margin: 0;
}

.header {
    width: 100%;
    margin-bottom: 10px;
}

.title {
    font-size: 20px;
    font-weight: bold;
}

.billing {
    font-size: 9px;
    margin-top: 5px;
}

.page {
    text-align: right;
    font-size: 8px;
}

table {
    width: 100%;
    border-collapse: collapse;
    table-layout: fixed;
}

th {
    background: #eeeeee;
    font-weight: bold;
}

th,
td {
    border: 1px solid #cccccc;
    padding: 3px;
    word-wrap: break-word;
}

th:nth-child(1),
td:nth-child(1) {
    width: 14%;
}

th:nth-child(2),
td:nth-child(2) {
    width: 14%;
}

th:nth-child(3),
td:nth-child(3) {
    width: 10%;
}

th:nth-child(4),
td:nth-child(4) {
    width: 10%;
}

th:nth-child(5),
td:nth-child(5) {
    width: 8%;
}

th:nth-child(6),
td:nth-child(6) {
    width: 8%;
}

th:nth-child(7),
td:nth-child(7) {
    width: 18%;
}

th:nth-child(8),
td:nth-child(8) {
    width: 18%;
}

</style>

</head>

<body>

<div class="header">

    <div class="title">
        Invoice
    </div>

    <div class="billing">
        Billing Start Date:
        ${this.escapeHtml(this.billingStartDate)}
    </div>

    <div class="billing">
        Billing End Date:
        ${this.escapeHtml(this.billingEndDate)}
    </div>

    <div class="page">
        Page ${pageNumber} of ${totalPages}
    </div>

</div>

<table>

<thead>

<tr>
    <th>From Number</th>
    <th>To Number</th>
    <th>Duration</th>
    <th>Direction</th>
    <th>Price</th>
    <th>Unit</th>
    <th>Start Time</th>
    <th>End Time</th>
</tr>

</thead>

<tbody>

${rows}

</tbody>

</table>

</body>
</html>
`;
    }

    /* ------------------------------------------------------------
     * HELPERS
     * ------------------------------------------------------------ */

    escapeHtml(value) {

        if (value === null || value === undefined) {
            return '';
        }

        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    formatDateTime(value) {

        if (!value) {
            return '';
        }

        try {
            return new Date(value).toLocaleString();
        } catch (error) {
            return value;
        }
    }

    showToast(title, message, variant) {

        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }

    getErrorMessage(error) {

        if (!error) {
            return 'Unknown error.';
        }

        if (error.body && error.body.message) {
            return error.body.message;
        }

        if (error.message) {
            return error.message;
        }

        if (typeof error === 'string') {
            return error;
        }

        return 'Unknown error occurred.';
    }
}