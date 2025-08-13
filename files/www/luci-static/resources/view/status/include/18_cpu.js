'use strict';
'require baseclass';
'require fs';

document.head.append(E('style', { 'type': 'text/css' }, `
.cbi-progressbar {
  height: 1.5em;
}
`));

return baseclass.extend({
  title: _('CPU Load'),
  viewName: 'cpu_status',
  lastStatArray: null,

  parseProcData(data) {
    let cpuStatArray = [];
    let statItemsArray = data.trim().split('\n').filter(s => s.startsWith('cpu'));
    for (let str of statItemsArray) {
      let arr = str.split(/\s+/).slice(0, 8);
      arr[0] = (arr[0] === 'cpu') ? Infinity : arr[0].replace('cpu', '');
      cpuStatArray.push(arr.map(e => Number(e)));
    }
    cpuStatArray.sort((a, b) => a[0] - b[0]);
    return cpuStatArray;
  },

  calcCPULoad(cpuStatArray) {
    let retArray = [];
    cpuStatArray.forEach((c, i) => {
      let loadUser = 0, loadNice = 0, loadSys = 0, loadIdle = 0, loadIo = 0, loadIrq = 0, loadSirq = 0, loadAvg = 0;
      if (this.lastStatArray !== null && this.lastStatArray[i][0] === c[0]) {
        let user = c[1] - this.lastStatArray[i][1],
          nice = c[2] - this.lastStatArray[i][2],
          sys = c[3] - this.lastStatArray[i][3],
          idle = c[4] - this.lastStatArray[i][4],
          io = c[5] - this.lastStatArray[i][5],
          irq = c[6] - this.lastStatArray[i][6],
          sirq = c[7] - this.lastStatArray[i][7];

        let sum = user + nice + sys + idle + io + irq + sirq;
        if (sum > 0) {
          loadUser = Number((100 * user / sum).toFixed(1));
          loadNice = Number((100 * nice / sum).toFixed(1));
          loadSys = Number((100 * sys / sum).toFixed(1));
          loadIdle = Number((100 * idle / sum).toFixed(1));
          loadIo = Number((100 * io / sum).toFixed(1));
          loadIrq = Number((100 * irq / sum).toFixed(1));
          loadSirq = Number((100 * sirq / sum).toFixed(1));
          loadAvg = Math.round(100 * (user + nice + sys + io + irq + sirq) / sum);
        }
      }
      retArray.push({ cpuNum: c[0], loadUser, loadNice, loadSys, loadIdle, loadIo, loadIrq, loadSirq, loadAvg });
    });
    return retArray;
  },

  eachCPU: {
    makeTable() {
      this.table = E('table', { 'class': 'table' });
    },
    append(cpuNum, cpuLoadObj, cpuLoadFlag) {
      this.table.append(E('tr', { 'class': 'tr' }, [
        E('td', { 'class': 'td left', 'width': '33%' },
          (cpuNum === Infinity) ? _('Total load') : _('CPU') + ' ' + cpuNum),
        E('td', { 'class': 'td' }, E('div', {
          'class': 'cbi-progressbar',
          'title': (cpuLoadFlag) ? cpuLoadObj.loadAvg + '%' : _('Calculating') + '...'
        }, E('div', { 'style': 'width:' + cpuLoadObj.loadAvg + '%' })))
      ]));
    }
  },

  makeCPUTable(cpuLoadArray) {
    let currentView = this.eachCPU;
    currentView.makeTable();
    cpuLoadArray.forEach((c, i) => {
      currentView.append(c.cpuNum, c, (this.lastStatArray !== null));
    });
    return currentView.table;
  },

  load() {
    return L.resolveDefault(fs.read('/proc/stat'), null);
  },

  render(cpuData) {
    if (!cpuData) return;
    let cpuStatArray = this.parseProcData(cpuData);

    // Jika hanya ada satu CPU, tetap tampilkan sebagai CPU 0
    if (cpuStatArray.length === 2) {
      cpuStatArray = cpuStatArray.slice(1, 2);
    }

    let cpuLoadArray = this.calcCPULoad(cpuStatArray);
    let cpuTable = this.makeCPUTable(cpuLoadArray);

    this.lastStatArray = cpuStatArray;
    return E('div', { 'class': 'cbi-section' }, [cpuTable]);
  }
});