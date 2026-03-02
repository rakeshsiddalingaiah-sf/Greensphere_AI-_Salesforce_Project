import { LightningElement, api, wire, track } from 'lwc';
import { getRecord }                          from 'lightning/uiRecordApi';
import { ShowToastEvent }                     from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import ESG_CHANNEL                            from '@salesforce/messageChannel/ESGDataChannel__c';

// Apex imports
import getEmissionSummary    from '@salesforce/apex/EmissionCalculatorService.getEmissionSummary';
import getHighRiskSuppliers  from '@salesforce/apex/SupplierRiskService.getHighRiskSuppliers';
import getComplianceSummary  from '@salesforce/apex/ComplianceRiskEngine.getComplianceSummary';
import generateReport        from '@salesforce/apex/ESGReportGeneratorService.generateExecutiveSummary';

export default class EsgDashboard extends LightningElement {
    @api recordId;

    @track scope1Data      = [];
    @track scope2Data      = [];
    @track scope3Data      = [];
    @track chartLabels     = [];
    @track esgScore        = '--';
    @track totalEmissions  = 0;
    @track complianceRate  = '--';
    @track highRiskSupplierCount = 0;
    @track showReportModal = false;
    @track isGeneratingReport = false;
    @track generatedReport = null;
    @track showToast       = false;
    @track toastMessage    = '';
    @track chartViewMode   = 'monthly';

    // Compliance summary
    @track complianceSummary = {};
    @track onTrackCount  = 0;
    @track atRiskCount   = 0;

    subscription = null;
    currentYear  = new Date().getFullYear();

    connectedCallback() {
        this.loadDashboardData();
        this.subscribeToMessages();
    }

    disconnectedCallback() {
        this.unsubscribeFromMessages();
    }

    @wire(MessageContext)
    messageContext;

    subscribeToMessages() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                ESG_CHANNEL,
                (message) => this.handleMessage(message)
            );
        }
    }

    unsubscribeFromMessages() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    handleMessage(message) {
        if (message.type === 'EMISSION_SAVED') {
            this.loadDashboardData();
        }
    }

    async loadDashboardData() {
        try {
            await Promise.all([
                this.loadEmissionData(),
                this.loadComplianceSummary(),
                this.loadSupplierRisk()
            ]);
        } catch (error) {
            console.error('Dashboard load error:', error);
        }
    }

    async loadEmissionData() {
        if (!this.recordId) return;
        try {
            const summary = await getEmissionSummary({
                accountId : this.recordId,
                startDate : `${this.currentYear}-01-01`,
                endDate   : `${this.currentYear}-12-31`
            });
            if (summary) {
                this.totalEmissions = summary.grandTotal || 0;
                this.scope1Data     = [summary.scope1Total || 0];
                this.scope2Data     = [summary.scope2Total || 0];
                this.scope3Data     = [summary.scope3Total || 0];
            }
        } catch (err) {
            console.error('Emission data error:', err);
        }
    }

    async loadComplianceSummary() {
        if (!this.recordId) return;
        try {
            const summary = await getComplianceSummary({ accountId: this.recordId });
            if (summary && summary.totalRegulations > 0) {
                this.onTrackCount = summary.onTrackCount || 0;
                this.atRiskCount  = summary.atRiskCount  || 0;
                this.complianceRate = Math.round(
                    (this.onTrackCount / summary.totalRegulations) * 100
                );
                this.complianceSummary = summary;
            }
        } catch (err) {
            console.error('Compliance summary error:', err);
        }
    }

    async loadSupplierRisk() {
        if (!this.recordId) return;
        try {
            const suppliers = await getHighRiskSuppliers();
            this.highRiskSupplierCount = suppliers ? suppliers.length : 0;
        } catch (err) {
            console.error('Supplier risk error:', err);
        }
    }

    async handleGenerateReport() {
        this.showReportModal     = true;
        this.isGeneratingReport  = true;
        this.generatedReport     = null;

        try {
            const report = await generateReport({
                accountId  : this.recordId,
                periodYear : this.currentYear
            });
            this.generatedReport    = report;
            this.isGeneratingReport = false;
        } catch (error) {
            this.isGeneratingReport = false;
            this.dispatchEvent(new ShowToastEvent({
                title   : 'Report Generation Failed',
                message : 'Unable to generate AI report: ' + (error.body?.message || error.message),
                variant : 'error'
            }));
        }
    }

    handleEmissionSaved(event) {
        this.showSuccessToast('Emission record saved successfully!');
        this.loadEmissionData();
    }

    handleComplianceAnalyzed(event) {
        this.loadComplianceSummary();
    }

    handleSupplierRiskUpdated(event) {
        this.highRiskSupplierCount = event.detail.highRiskCount || 0;
    }

    handleMonthlyView()    { this.chartViewMode = 'monthly';    }
    handleQuarterlyView()  { this.chartViewMode = 'quarterly';  }

    closeReportModal()  { this.showReportModal = false; }

    handleExportReport() {
        this.showSuccessToast('Export functionality — connect to ContentVersion or Document generation tool.');
    }

    showSuccessToast(message) {
        this.dispatchEvent(new ShowToastEvent({
            title   : 'Success',
            message : message,
            variant : 'success'
        }));
    }

    // Computed properties
    get formattedTotalEmissions() {
        return this.totalEmissions
            ? parseFloat(this.totalEmissions).toLocaleString('en-US', { maximumFractionDigits: 1 })
            : '0';
    }

    get emissionTrend()   { return 'down'; }
    get scoreTrend()      { return 'up';   }
    get supplierTrend()   { return this.highRiskSupplierCount > 5 ? 'up' : 'neutral'; }
    get monthlyVariant()  { return this.chartViewMode === 'monthly'    ? 'brand' : 'neutral'; }
    get quarterlyVariant(){ return this.chartViewMode === 'quarterly'  ? 'brand' : 'neutral'; }

    get complianceColor() {
        const rate = Number(this.complianceRate);
        if (rate >= 80) return 'green';
        if (rate >= 60) return 'yellow';
        return 'red';
    }

    get complianceSummaryLabel() {
        return `${this.onTrackCount} On Track · ${this.atRiskCount} At Risk`;
    }

    get complianceBadgeClass() {
        return this.atRiskCount > 0
            ? 'slds-badge_lightest slds-theme_warning'
            : 'slds-badge_lightest slds-theme_success';
    }
}
