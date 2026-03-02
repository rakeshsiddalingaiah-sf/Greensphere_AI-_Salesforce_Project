import { LightningElement, api } from 'lwc';

export default class EsgReportGenerator extends LightningElement {
    @api accountId;
    @api reportData;

    get scope1Formatted()  { return this.formatNum(this.reportData?.scope1); }
    get scope2Formatted()  { return this.formatNum(this.reportData?.scope2); }
    get scope3Formatted()  { return this.formatNum(this.reportData?.scope3); }
    get totalFormatted()   { return this.formatNum(this.reportData?.totalEmissions); }

    get formattedDate() {
        return this.reportData?.generatedDate
            ? new Date(this.reportData.generatedDate).toLocaleString()
            : '';
    }

    get scoreCircleStyle() {
        const score = this.reportData?.overallScore || 0;
        const color = score >= 70 ? '#2ecc71' : score >= 50 ? '#f39c12' : '#e74c3c';
        return `--score-color: ${color}; --score-pct: ${score}%`;
    }

    formatNum(val) {
        if (val == null) return '0';
        return parseFloat(val).toLocaleString('en-US', { maximumFractionDigits: 1 });
    }
}
