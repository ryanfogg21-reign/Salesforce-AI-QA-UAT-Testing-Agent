import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/Test_Script__c.Name';
import runScript from '@salesforce/apex/TestRunController.runScript';

export default class RunScriptAction extends NavigationMixin(LightningElement) {
    @api recordId;

    isRunning  = false;
    isDone     = false;
    resultIcon = '';
    resultMessage = '';

    @wire(getRecord, { recordId: '$recordId', fields: [NAME_FIELD] })
    record;

    get scriptName()      { return getFieldValue(this.record?.data, NAME_FIELD) ?? '…'; }
    get isLoadingRecord() { return !this.record?.data && !this.record?.error; }
    get runLabel()        { return this.isRunning ? 'Starting…' : 'Run Script'; }

    async handleRun() {
        this.isRunning = true;
        try {
            const result = await runScript({ testScriptId: this.recordId });
            this.isDone = true;
            if (result.success) {
                this.resultIcon    = 'utility:success';
                this.resultMessage = result.message;
                // Give the user a moment to read the confirmation before navigating
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.dispatchEvent(new CloseActionScreenEvent());
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: { recordId: result.testRunId, actionName: 'view' },
                    });
                }, 1500);
            } else {
                this.resultIcon    = 'utility:error';
                this.resultMessage = result.message;
            }
        } catch (err) {
            this.isDone        = true;
            this.resultIcon    = 'utility:error';
            this.resultMessage = err.body?.message ?? 'Unexpected error starting the test run.';
        } finally {
            this.isRunning = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
