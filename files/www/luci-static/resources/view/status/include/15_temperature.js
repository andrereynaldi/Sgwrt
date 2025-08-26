'use strict';
'require baseclass';
'require rpc';

document.head.append(E('style', {'type': 'text/css'}, `
:root {
 --app-temp-status-font-color: #2e2e2e;
 --app-temp-status-hot-color: #fff7e2;
 --app-temp-status-overheat-color: #ffe9e8;
}
:root[data-darkmode="true"] {
 --app-temp-status-font-color: #fff;
 --app-temp-status-hot-color: #8d7000;
 --app-temp-status-overheat-color: #a93734;
}
.temp-status-hot {
 background-color: var(--app-temp-status-hot-color) !important;
 color: var(--app-temp-status-font-color) !important;
}
.temp-status-hot .td {
 color: var(--app-temp-status-font-color) !important;
}
.temp-status-hot td {
 color: var(--app-temp-status-font-color) !important;
}
.temp-status-overheat {
 background-color: var(--app-temp-status-overheat-color) !important;
 color: var(--app-temp-status-font-color) !important;
}
.temp-status-overheat .td {
 color: var(--app-temp-status-font-color) !important;
}
.temp-status-overheat td {
 color: var(--app-temp-status-font-color) !important;
}
`));

return baseclass.extend({
    title: _('Temperature'),
    viewName: 'temp_status',
    tempHot: 45,
    tempOverheat: 60,
    sensorsData: null,
    tempData: null,
    sensorsPath: [],

    callSensors: rpc.declare({
        object: 'luci.temp-status',
        method: 'getSensors',
        expect: {'': {}},
    }),

    callTempData: rpc.declare({
        object: 'luci.temp-status',
        method: 'getTempData',
        params: ['tpaths'],
        expect: {'': {}},
    }),

    formatTemp(mc) {
        return Number((mc / 1000).toFixed(1));
    },

    sortFunc(a, b) {
        return (a.number > b.number) ? 1 : (a.number < b.number) ? -1 : 0;
    },

    makeTempTableContent() {
        let tempTable = E('table', {'class': 'table'});
        
        if (this.sensorsData && this.tempData) {
            for (let [k, v] of Object.entries(this.sensorsData)) {
                v.sort(this.sortFunc);
                for (let i of Object.values(v)) {
                    let sensor = i.title || i.item;
                    if (i.sources === undefined) {
                        continue;
                    };
                    i.sources.sort(this.sortFunc);
                    for (let j of i.sources) {
                        if (!j.path.includes('thermal_zone') && !j.path.includes('cpu_thermal')) {
                            continue;
                        }

                        let temp = this.tempData[j.path];

                        if (temp !== undefined && temp !== null) {
                            temp = this.formatTemp(temp);
                        };

                        let tempHot = NaN;
                        let tempOverheat = NaN;
                        let tpoints = j.tpoints;
                        let tpointsString = '';

                        if (tpoints) {
                            for (let i of Object.values(tpoints)) {
                                let t = this.formatTemp(i.temp);
                                tpointsString += `&#10;${i.type}: ${t} °C`;
                                if (i.type == 'max' || i.type == 'critical' || i.type == 'emergency') {
                                    if (!(tempOverheat <= t)) {
                                        tempOverheat = t;
                                    };
                                } else if (i.type == 'hot') {
                                    tempHot = t;
                                };
                            };
                        };

                        if (isNaN(tempHot) && isNaN(tempOverheat)) {
                            tempHot = this.tempHot;
                            tempOverheat = this.tempOverheat;
                        };

                        let rowStyle = (temp >= tempOverheat) ? ' temp-status-overheat' : (temp >= tempHot) ? ' temp-status-hot' : '';

                        tempTable.append(E('tr', {
                            'class': 'tr' + rowStyle,
                            'data-path': j.path,
                        }, [
                            E('td', {
                                'class': 'td left',
                                'data-title': _('Sensor')
                            }, 'CPU Temperature'),
                            E('td', {
                                'class': 'td right',
                                'data-title': _('Temperature')
                            }, (temp === undefined || temp === null) ? '-' : temp + ' °C'),
                        ]));
                    };
                };
            };
        };

        if (tempTable.childNodes.length == 0) {
            tempTable.append(E('tr', {'class': 'tr placeholder'}, E('td', {
                'class': 'td',
                'colspan': '2'
            }, E('em', {}, _('No temperature sensors available')))));
        };
        
        return tempTable;
    },

    load() {
        return L.resolveDefault(this.callSensors(), null);
    },

    render(data) {
        if (data) {
            if (!this.sensorsData) {
                this.sensorsData = data.sensors;
                this.sensorsPath = data.temp && new Array(...Object.keys(data.temp));
            };
            this.tempData = data.temp;
        };

        if (!this.sensorsData || !this.tempData) {
            return E('div', {}, _('Loading temperature data...'));
        };

        return E('div', {'class': 'cbi-section'}, this.makeTempTableContent());
    },
});
