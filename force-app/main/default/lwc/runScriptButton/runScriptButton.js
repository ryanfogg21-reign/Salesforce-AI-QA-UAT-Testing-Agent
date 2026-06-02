import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import runScript from '@salesforce/apex/TestRunController.runScript';

export default class RunScriptButton extends NavigationMixin(LightningElement) {
    @api recordId;
    isRunning = false;

    async handleRun() {
        this.isRunning = true;
        try {
            const result = await runScript({ testScriptId: this.recordId });
            if (result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Test Run Started',
                    message: result.message,
                    variant: 'success',
                }));
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: { recordId: result.testRunId, actionName: 'view' },
                });
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Cannot Start Run',
                    message: result.message,
                    variant: 'error',
                }));
            }
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: err.body?.message ?? 'Unexpected error starting the test run.',
                variant: 'error',
            }));
        } finally {
            this.isRunning = false;
        }
    }
}
