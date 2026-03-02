import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent }               from 'lightning/platformShowToastEvent';
import { createRecord }                 from 'lightning/uiRecordApi';
import EMISSION_RECORD_OBJECT           from '@salesforce/schema/Emission_Record__c';
import COMPANY_FIELD                    from '@salesforce/schema/Emission_Record__c.Company__c';
import SCOPE_TYPE_FIELD                 from '@salesforce/schema/Emission_Record__c.Scope_Type__c';
import SOURCE_CATEGORY_FIELD            from '@salesforce/schema/Emission_Record__c.Source_Category__c';
import ACTIVITY_VALUE_FIELD             from '@salesforce/schema/Emission_Record__c.Activity_Value__c';
import CARBON_OFFSET_FIELD              from '@salesforce/schema/Emission_Record__c.Carbon_Offset__c';
import EMISSION_DATE_FIELD              from '@salesforce/schema/Emission_Record__c.Emission_Date__c';

const EMISSION_FACTORS = {
    'Scope 1': {
        'Natural Gas' : 2.204,
        'Diesel'      : 2.68,
        'Petrol'      : 2.31,
        'LPG'         : 1.51,
        'Coal'        : 2.42,
        'Heating Oil' : 2.52
    },
    'Scope 2': {
        'Grid Electricity US'    : 0.386,
        'Grid Electricity EU'    : 0.276,
        'Grid Electricity India' : 0.708,
        'Grid Electricity China' : 0.555,
        'Renewable Energy'       : 0.0
    },
    'Scope 3': {
        'Business Travel - Air' : 0.255,
        'Business Travel - Rail': 0.041,
        'Employee Commute'      : 0.171,
        'Waste - Landfill'      : 0.467,
        'Waste - Recycled'      : 0.021
    }
};

const SCOPE_DESCRIPTIONS = {
    'Scope 1': 'Direct emissions from owned/controlled sources (combustion, vehicles, on-site equipment)',
    'Scope 2': 'Indirect emissions from purchased electricity, heat, or steam',
    'Scope 3': 'All other indirect emissions across value chain (travel, waste, supply chain)'
};

export default class CarbonTracker extends LightningElement {
    @api accountId;

    @track selectedScope    = 'Scope 1';
    @track selectedCategory = '';
    @track activityValue    = '';
    @track carbonOffset     = 0;
    @track emissionDate     = new Date().toISOString().split('T')[0];
    @track isSaving         = false;

    handleCategoryChange(e) { this.selectedCategory = e.detail.value; }
    handleActivityValueChange(e) { this.activityValue = e.detail.value; }
    handleDateChange(e)     { this.emissionDate = e.detail.value; }
    handleOffsetChange(e)   { this.carbonOffset = parseFloat(e.detail.value) || 0; }

    selectScope1() { this.selectedScope = 'Scope 1'; this.selectedCategory = ''; }
    selectScope2() { this.selectedScope = 'Scope 2'; this.selectedCategory = ''; }
    selectScope3() { this.selectedScope = 'Scope 3'; this.selectedCategory = ''; }

    get categoryOptions() {
        const cats = EMISSION_FACTORS[this.selectedScope] || {};
        return Object.keys(cats).map(k => ({ label: k, value: k }));
    }

    get scopeDescription()  { return SCOPE_DESCRIPTIONS[this.selectedScope]; }
    get scopeIconName()     { return 'utility:info'; }

    get activityValueLabel() {
        const units = {
            'Scope 1': 'Quantity (m³ / litres / kg)',
            'Scope 2': 'Electricity Consumed (kWh)',
            'Scope 3': 'Distance / Weight (km or kg)'
        };
        return units[this.selectedScope] || 'Activity Value';
    }

    get calculatedGross() {
        const factor = (EMISSION_FACTORS[this.selectedScope] || {})[this.selectedCategory] || 0;
        return ((parseFloat(this.activityValue) || 0) * factor / 1000).toFixed(3);
    }

    get calculatedNet() {
        const net = parseFloat(this.calculatedGross) - (this.carbonOffset || 0);
        return Math.max(0, net).toFixed(3);
    }

    get showCalculation() {
        return this.activityValue && parseFloat(this.activityValue) > 0 && this.selectedCategory;
    }

    get scope1TabClass() { return `scope-tab ${this.selectedScope === 'Scope 1' ? 'active' : ''}`; }
    get scope2TabClass() { return `scope-tab ${this.selectedScope === 'Scope 2' ? 'active' : ''}`; }
    get scope3TabClass() { return `scope-tab ${this.selectedScope === 'Scope 3' ? 'active' : ''}`; }

    async handleSave() {
        if (!this.accountId || !this.selectedCategory || !this.activityValue) {
            this.showToast('Validation Error', 'Please fill in all required fields.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            const fields = {};
            fields[COMPANY_FIELD.fieldApiName]        = this.accountId;
            fields[SCOPE_TYPE_FIELD.fieldApiName]     = this.selectedScope;
            fields[SOURCE_CATEGORY_FIELD.fieldApiName]= this.selectedCategory;
            fields[ACTIVITY_VALUE_FIELD.fieldApiName] = parseFloat(this.activityValue);
            fields[CARBON_OFFSET_FIELD.fieldApiName]  = this.carbonOffset || 0;
            fields[EMISSION_DATE_FIELD.fieldApiName]  = this.emissionDate;

            const result = await createRecord({ apiName: EMISSION_RECORD_OBJECT.objectApiName, fields });
            this.showToast('Saved', `Emission record created (${this.calculatedNet} tCO₂e net)`, 'success');
            this.dispatchEvent(new CustomEvent('recordsaved', { detail: { recordId: result.id } }));
            this.handleClear();
        } catch (error) {
            this.showToast('Error', error.body?.message || 'Failed to save record.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleClear() {
        this.selectedCategory = '';
        this.activityValue    = '';
        this.carbonOffset     = 0;
        this.emissionDate     = new Date().toISOString().split('T')[0];
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
