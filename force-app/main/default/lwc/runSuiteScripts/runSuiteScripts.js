import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getScriptsForSuite from '@salesforce/apex/TestRunController.getScriptsForSuite';
import runScript from '@salesforce/apex/TestRunController.runScript';

const COLUMNS = [
    { label: 'Script Name',     fieldName: 'Name',               type: 'text' },
    { label: 'Priority',        fieldName: 'Priority__c',         type: 'text' },
    { label: 'Last Run Status', fieldName: 'Last_Run_Status__c',  type: 'text' },
    { label: 'Last Run Date',   fieldName: 'Last_Run_Date__c',    type: 'date',
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit',
                        hour: '2-digit', minute: '2-digit' } },
];

export default class RunSuiteScripts extends LightningElement {
    @api recordId;

    @track isModalOpen  = false;
    @track isLoading    = false;
    @track isRunning    = false;
    @track scripts      = [];
    @track selectedIds  = [];

    columns = COLUMNS;

    get hasScripts()         { return this.scripts.length > 0; }
    get isRunButtonDisabled() { return this.selectedIds.length === 0 || this.isRunning; }
    get runButtonLabel() {
        if (this.isRunning) return 'Starting…';
        const n = this.selectedIds.length;
        return n === 0 ? 'Run Selected' : `Run Selected (${n})`;
    }

    async openModal() {
        this.isModalOpen = true;
        this.isLoading   = true;
        this.selectedIds = [];
        try {
            this.scripts = await getScriptsForSuite({ testSuiteId: this.recordId });
        } catch (err) {
            this.showToast('Error loading scripts',
                err.body?.message ?? 'Could not retrieve scripts for this suite.', 'error');
            this.isModalOpen = false;
        } finally {
            this.isLoading = false;
        }
    }

    closeModal() {
        this.isModalOpen = false;
        this.selectedIds = [];
    }

    handleSelection(evt) {
        this.selectedIds = evt.detail.selectedRows.map(r => r.Id);
    }

    async handleRunSelected() {
        this.isRunning = true;
        let passed = 0;
        let failed = 0;

        for (const scriptId of this.selectedIds) {
            try {
                const res = await runScript({ testScriptId: scriptId });
                res.success ? passed++ : failed++;
            } catch {
                failed++;
            }
        }

        this.showToast(
            'Runs Queued',
            `${passed} run(s) started successfully${failed > 0 ? `, ${failed} failed to start` : ''}.`,
            passed > 0 ? 'success' : 'error'
        );

        this.isRunning = false;
        this.closeModal();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
