import { LightningElement, api, track } from 'lwc';
import { subscribe, unsubscribe, onError, setDebugFlag, isEmpEnabled }
    from 'lightning/empApi';

export default class AlertsPanel extends LightningElement {
    @api accountId;
    @track alerts       = [];
    @track subscription = null;
    alertCounter        = 0;

    channelName = '/event/ESG_Alert__e';

    connectedCallback() {
        this.subscribeToAlerts();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription, response => {
                console.log('Unsubscribed from ESG_Alert__e:', response);
            });
        }
    }

    subscribeToAlerts() {
        const replayId = -1; // -1 = new events only

        subscribe(this.channelName, replayId, event => {
            const payload = event.data.payload;

            // Filter to relevant account if recordId provided
            if (this.accountId && payload.Account_Id__c !== this.accountId) return;

            this.addAlert({
                id         : ++this.alertCounter,
                severity   : payload.Severity__c   || 'Info',
                message    : payload.Message__c     || 'ESG alert received',
                alertType  : payload.Alert_Type__c  || 'GENERAL',
                timestamp  : new Date()
            });
        }).then(sub => {
            this.subscription = sub;
        }).catch(err => {
            console.error('EMP API subscription error:', err);
            // Load mock data in dev environments without Platform Events
            this.loadMockAlerts();
        });

        onError(error => {
            console.error('EMP API error:', error);
        });
    }

    addAlert(alert) {
        this.alerts = [
            {
                ...alert,
                timeAgo     : 'Just now',
                alertClass  : `alert-item severity-${alert.severity.toLowerCase()}`,
                severityClass: `severity-badge ${alert.severity.toLowerCase()}`,
            },
            ...this.alerts
        ].slice(0, 20); // Keep max 20 alerts
    }

    loadMockAlerts() {
        this.alerts = [
            {
                id: 1,
                severity: 'High',
                message: 'Emissions approaching CSRD threshold (87% of limit)',
                alertType: 'EMISSION_THRESHOLD_BREACH',
                timeAgo: '5 min ago',
                alertClass: 'alert-item severity-high',
                severityClass: 'severity-badge high'
            },
            {
                id: 2,
                severity: 'Medium',
                message: 'Compliance deadline for SEC Climate Rule in 21 days',
                alertType: 'COMPLIANCE_DEADLINE_APPROACHING',
                timeAgo: '1 hr ago',
                alertClass: 'alert-item severity-medium',
                severityClass: 'severity-badge medium'
            },
            {
                id: 3,
                severity: 'Low',
                message: 'Supplier GreenLogistics Co. ESG rating updated to B',
                alertType: 'SUPPLIER_RISK_HIGH',
                timeAgo: '2 hrs ago',
                alertClass: 'alert-item severity-low',
                severityClass: 'severity-badge low'
            }
        ];
    }

    dismissAlert(event) {
        const alertId = parseInt(event.currentTarget.dataset.id);
        this.alerts = this.alerts.filter(a => a.id !== alertId);
    }

    clearAllAlerts() {
        this.alerts = [];
    }

    get hasAlerts()  { return this.alerts && this.alerts.length > 0; }
    get alertCount() { return this.alerts ? this.alerts.length : 0;  }
}
