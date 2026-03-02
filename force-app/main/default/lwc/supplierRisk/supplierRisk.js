import { LightningElement, api, track, wire } from 'lwc';
import getHighRiskSuppliers from '@salesforce/apex/SupplierRiskService.getHighRiskSuppliers';

export default class SupplierRisk extends LightningElement {
    @api accountId;
    @track suppliers   = [];
    @track isLoading   = true;
    @track error       = null;

    connectedCallback() {
        this.loadSupplierData();
    }

    async loadSupplierData() {
        this.isLoading = true;
        try {
            const rawSuppliers = await getHighRiskSuppliers();
            this.suppliers = (rawSuppliers || []).map(s => ({
                ...s,
                rowClass      : `table-row risk-${(s.riskLevel || 'low').toLowerCase()}`,
                ratingClass   : `rating-badge rating-${(s.esgRating || 'C').toLowerCase()}`,
                statusClass   : `status-badge status-${(s.complianceStatus || '').replace(/ /g, '-').toLowerCase()}`,
                scope3Formatted: s.scope3Contribution
                    ? parseFloat(s.scope3Contribution).toLocaleString('en-US', { maximumFractionDigits: 0 })
                    : '0',
                riskBarStyle  : `width: ${Math.min(s.riskScore || 0, 100)}%; background: ${this.getRiskColor(s.riskScore)}`
            }));

            // Dispatch event with high risk count
            const highCount = this.suppliers.filter(s => s.riskLevel === 'High').length;
            this.dispatchEvent(new CustomEvent('riskcalculated', {
                detail: { highRiskCount: highCount },
                bubbles: true
            }));
        } catch (err) {
            console.error('Supplier Risk error:', err);
            this.error = err;
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.loadSupplierData();
    }

    getRiskColor(score) {
        if (score >= 70) return '#e74c3c';
        if (score >= 40) return '#f39c12';
        return '#2ecc71';
    }

    get hasSuppliers() { return this.suppliers && this.suppliers.length > 0; }
    get highCount()    { return this.suppliers.filter(s => s.riskLevel === 'High').length;   }
    get mediumCount()  { return this.suppliers.filter(s => s.riskLevel === 'Medium').length; }
    get lowCount()     { return this.suppliers.filter(s => s.riskLevel === 'Low').length;    }
}
