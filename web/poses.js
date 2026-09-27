/* Pack de poses intégré : des squelettes dessinés en SVG à la volée.
   Aucun fichier image, rien à télécharger, utilisable hors-ligne dès l'installation. */
'use strict';
(function () {
  // Repère : viewBox -20 -20 240 420, silhouette debout d'environ 330 unités.
  const BASE = {
    head: [100, 55], neck: [100, 82], lsh: [76, 92], rsh: [124, 92],
    hip: [100, 200], lhip: [89, 202], rhip: [111, 202],
  };
  const pose = (id, name, tip, joints) => ({ id, name, tip, j: Object.assign({}, BASE, joints) });

  const PACK = [
    pose('casual', 'Décontracté·e',
      'Poids sur une jambe, mains dans les poches, épaules basses.',
      { lel: [70, 145], lwr: [86, 194], rel: [130, 145], rwr: [114, 194],
        lkn: [86, 290], lan: [84, 378], rkn: [118, 288], ran: [128, 372] }),

    pose('walk', 'La marche',
      'Marche lentement vers l’objectif en regardant ailleurs. Active la rafale.',
      { head: [102, 55], lsh: [77, 92], rsh: [123, 92], hip: [100, 198], lhip: [89, 200], rhip: [111, 200],
        lel: [70, 142], lwr: [74, 190], rel: [132, 140], rwr: [140, 186],
        lkn: [82, 285], lan: [88, 372], rkn: [122, 280], ran: [112, 360] }),

    pose('shoulder', 'Par-dessus l’épaule',
      'Dos à l’objectif, tourne seulement la tête et une épaule.',
      { head: [114, 57], neck: [102, 82], rsh: [126, 88],
        lel: [72, 146], lwr: [74, 198], rel: [128, 146], rwr: [126, 198],
        lkn: [90, 290], lan: [90, 378], rkn: [114, 290], ran: [116, 378] }),

    pose('open', 'Face au paysage',
      'Bras ouverts vers le ciel. Le photographe se baisse pour allonger la silhouette.',
      { lel: [46, 48], lwr: [24, 4], rel: [154, 48], rwr: [176, 4],
        lkn: [80, 290], lan: [70, 378], rkn: [120, 290], ran: [130, 378] }),

    pose('lean', 'Appuyé·e',
      'Un coude sur une rambarde, chevilles croisées, regard au loin.',
      { head: [86, 58], neck: [92, 84], lsh: [70, 96], rsh: [116, 90],
        hip: [104, 200], lhip: [93, 202], rhip: [115, 198],
        lel: [58, 148], lwr: [52, 196], rel: [150, 128], rwr: [170, 168],
        lkn: [100, 288], lan: [122, 376], rkn: [118, 286], ran: [100, 378] }),

    pose('seated', 'Assis·e',
      'Sur une marche, dos droit, mains jointes entre les genoux.',
      { head: [100, 120], neck: [100, 146], lsh: [78, 156], rsh: [122, 156],
        hip: [100, 258], lhip: [89, 260], rhip: [111, 260],
        lel: [70, 208], lwr: [96, 248], rel: [130, 208], rwr: [104, 248],
        lkn: [72, 282], lan: [78, 370], rkn: [128, 280], ran: [122, 368] }),

    pose('hair', 'Main dans les cheveux',
      'Une main dans les cheveux, l’autre relâchée, regard hors champ.',
      { head: [96, 56], rel: [150, 52], rwr: [116, 30], lel: [70, 146], lwr: [74, 198],
        lkn: [88, 290], lan: [86, 378], rkn: [114, 288], ran: [124, 374] }),

    pose('point', 'Regarde là-bas',
      'Montre un détail hors champ et suis-le du regard.',
      { head: [92, 56], lel: [30, 76], lwr: [-8, 58], rel: [148, 140], rwr: [118, 184],
        lkn: [84, 290], lan: [78, 378], rkn: [116, 290], ran: [122, 378] }),
  ];

  /** Rend un squelette en SVG : trait blanc épais, liseré sombre pour rester lisible sur un ciel clair. */
  function poseSVG(j, width) {
    const w = width || 480;
    const pt = k => j[k][0] + ' ' + j[k][1];
    const chain = keys => 'M' + keys.map(pt).join('L');
    const [hx, hy] = j.head, [nx, ny] = j.neck;
    const R = 19, d = Math.hypot(nx - hx, ny - hy) || 1;
    const chin = [(hx + (nx - hx) / d * R).toFixed(1), (hy + (ny - hy) / d * R).toFixed(1)];
    const path =
      chain(['lwr', 'lel', 'lsh', 'rsh', 'rel', 'rwr']) +
      'M' + chin.join(' ') + 'L' + pt('neck') + 'L' + pt('hip') +
      chain(['lan', 'lkn', 'lhip', 'rhip', 'rkn', 'ran']);
    const shape = `<path d="${path}"/><circle cx="${hx}" cy="${hy}" r="${R}"/>`;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-20 -20 240 420" width="${w}" height="${Math.round(w * 420 / 240)}">` +
      `<g fill="none" stroke-linecap="round" stroke-linejoin="round">` +
      `<g stroke="rgba(0,0,0,0.45)" stroke-width="13">${shape}</g>` +
      `<g stroke="#fff" stroke-width="7">${shape}</g></g></svg>`;
  }

  window.POSE_PACK = PACK;
  window.poseSVG = poseSVG;
})();
