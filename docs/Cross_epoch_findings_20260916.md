# Diagnostica tra epoche: esiti e limiti

Analisi eseguita il 16 settembre 2026 su 160 meeting del 2000–2012 e 111 del 2013–2025. Si usano gli archivi già aperti forniti dall'autore; non è una nuova conferma né un rilancio dei 28 step. Tutti i nuovi risultati sono esplorativi. Il test settoriale è bilaterale, non scelto nella direzione osservata.

## Esito operativo

La quadratica non è una buona specificazione primaria per descrivere questi campioni. La relazione tra ampiezza delle due coordinate e proxy bipower anomala sopravvive al confronto tra epoche. L'ordinamento MP–CBI è sensibile alla forma angolare anche quando la crescita radiale è lineare. La composizione conta, ma i dati non autorizzano a sostituire «inversione» con «sola composizione». Queste sono conclusioni diverse e non vanno fuse in un solo verdetto.

## Provenienza e comparabilità

Il campione recente viene dal build congelato dell'11 settembre (`final_resume_20260911_174739_4124`), con manifest SHA256 `d7ef6b78ccb6be4283a196da4afe3c55458b25e8147c225b5b595454bf281b85`. Ho riprodotto il ponte del 12 settembre: con azionario EA, media MP 0,1819036957 e MP–CBI 0,0733387017. Il confronto qui riguarda questo campione documentato, non un ipotetico ultimo rerun della pipeline.

Il campione storico viene dalla ristima dopo apertura del 15 settembre, manifest del build `f3880de1a82a841373ffee1ac4c7383b56879061e6ea8a9bbdc4c9d6b3f81527`. Ho riprodotto i suoi outcome e stati cross-fitted dai controlli archiviati. Nessun prezzo grezzo è stato riletto.

L'outcome è quello Bund PR: log della proxy bipower meno continuazione normale stimata sui giorni di controllo. Le cinque barre hanno endpoint +5,+10,+15,+20,+25: supporto effettivo **(0,+25]**, non (+5,+25]. Sono stati verificati definizioni archiviate, numerosità delle barre e copertura, senza una nuova certificazione dai prezzi. Si mantiene la stessa fonte azionaria esterna EA in entrambe le epoche: non si mescolano fx futures recenti e azionario esterno storico. Questo non rende la finestra esterna identica alla finestra Schatz.

Per i contrasti tra epoche, entrambe le coordinate sono espresse nella metrica di generazione: SD Schatz sui controlli PR 0,00017367797; SD azionario EA sugli eventi recenti, in rendimento frazionario, 0,00422300643. Lo stato è pre-PR log BV, centrato e scalato sui controlli Bund PR recenti. Le analisi native mantengono invece le rispettive standardizzazioni leave-year-out.

Lo stato lento è uniformato ai cinque giorni di controllo precedenti, escludendo i giorni evento. Le continuazioni restano stimate separatamente per epoca, con validazione leave-year-out e dummy del cambio d'orario 2022 nel periodo recente; prima del 2013 quella dummy è identicamente zero. La correzione modifica l'outcome recente di 0,01852 in valore assoluto medio, massimo 0,04101, senza cambiare i 111 meeting. Le diagnosi sostanziali restano uguali.

## 1. La penalizzazione predittiva della quadratica si ripresenta

Errore quadratico medio, media a pesi uguali dei 13 anni lasciati fuori. Per il periodo recente si riportano stato lento armonizzato e stato d'interazione nativo leave-year-out.

| Forma | 2000–2012 | 2013–2025 |
|---|---:|---:|
| Profilo angolare quadratico, raggio al quadrato | 1,6451 | 2,7963 |
| Stesso profilo angolare, raggio lineare | **1,1330** | **1,3183** |
| Profilo angolare assoluto, raggio lineare | 1,1332 | 1,3708 |
| Profilo angolare assoluto, raggio al quadrato | 1,6641 | 2,9381 |
| Riferimento spline naturale con scelta interna della penalità | 1,6949 | 1,9469 |

A parità di profilo angolare quadratico, la crescita lineare riduce l'MSE del 31% e del 53%, vincendo rispettivamente in 12/13 e 11/13 anni. Il risultato è descrittivo: i fold condividono dati di addestramento e non costituiscono 13 esperimenti indipendenti. Inoltre la validazione è condizionale all'outcome e agli indicatori già costruiti, non una validazione integralmente annidata di tutta la pipeline. Non prova una legge esatta r^1, ma rende ingiustificato imporre r^2 come unica lente.

## 2. L'ampiezza di policy non scompare controllando per l'azionario

Nel ramo firmato/assoluto con entrambe le coordinate e tutte le rispettive interazioni con lo stato:

| Termine | 2000–2012: coefficiente; p Holm-9 | 2013–2025: coefficiente; p Holm-9 |
|---|---:|---:|
| Valore assoluto Schatz | 0,3727; **0,0108** | 0,3047; **0,0036** |
| Valore assoluto azionario | 0,6912; **0,0348** | 0,8598; **0,0092** |

I coefficienti della tabella usano le metriche native: non si confronta la loro grandezza tra epoche. Entrambe le associazioni positive sopravvivono alla correzione entro la famiglia dei nove termini in ciascuna epoca. Questo contraddice la lettura secondo cui nel periodo antico il contenuto di volatilità sarebbe esclusivamente azionario e il tasso privo di contenuto. Resta un'associazione condizionale, non l'identificazione causale di due shock strutturali. Le correzioni riportate non coprono retroattivamente l'intero percorso esplorativo del progetto.

## 3. Il settore recente dipende dalla forma angolare

Con la crescita lineare nel raggio e il profilo angolare quadratico, nel 2013–2025 il contrasto MP–CBI nella metrica nativa è **+0,3304**, p wild bilaterale **0,00635**, Holm sui quattro modelli **0,0254**. Nel 2000–2012 è −0,1873, p 0,2257.

La forma assoluta, che predice quasi altrettanto bene, dà invece +0,2123 nel periodo recente, p 0,18445; nel periodo antico −0,1795, p 0,24235. Dunque non è corretto dire che nessuna specificazione trova un ordinamento recente. Non è neppure corretto dire che l'ordinamento sia robusto alla forma funzionale.

Il confronto diretto nella **stessa metrica** e allo stesso raggio/stato fornisce:

| Modello | Storico MP–CBI | Recente MP–CBI | Differenza recente − storico | p wild differenza | Holm-12 |
|---|---:|---:|---:|---:|---:|
| Quadratico | −0,0994 | +0,0711 | +0,1705 | 0,02170 | 0,2170 |
| Angoli quadratici, raggio lineare | −0,2043 | +0,3464 | +0,5507 | 0,01145 | 0,12595 |
| Angoli assoluti, raggio lineare | −0,2011 | +0,2260 | +0,4270 | 0,07390 | 0,6651 |
| Angoli assoluti, raggio quadratico | −0,0944 | +0,0460 | +0,1405 | 0,08645 | 0,6916 |

La famiglia esplorativa di 12 test contiene quattro modelli per tre contrasti: ciascuna epoca e la differenza. La differenza nel modello a raggio lineare e angoli quadratici è interessante, ma non sopravvive a questa famiglia. Non si può dedurre uguaglianza dal mancato rifiuto, né una spiegazione economica della crisi dal cambio di segno puntuale.

## 4. Composizione: un contributo concreto, non una spiegazione esclusiva

Gli eventi esattamente sugli assi non appartengono ad alcuno dei due settori aperti: sono 22 storici e 16 recenti. Restano inclusi nelle stime delle superfici. Fra gli altri, i conteggi sono 60 MP e 78 CBI nel periodo antico, 63 MP e 32 CBI nel recente. Nel terzile superiore del raggio recente si trovano 32 MP contro appena 5 CBI: la comparabilità nelle code è limitata.

L'intersezione degli inviluppi convessi in (|u|, |z|, stato), fra tutte e quattro le celle epoca-settore, conserva 24 MP e 44 CBI storici, 27 MP e 10 CBI recenti. È un controllo geometrico di supporto, non una garanzia di densità. Il ripiegamento in valori assoluti sfrutta la simmetria centrale imposta dalle forme considerate.

Standardizzando su **identiche ampiezze delle due coordinate e identico stato**, con una distribuzione empirica comune bilanciata tra le quattro celle, il modello a raggio lineare e angoli quadratici dà −0,2392 nel periodo antico e +0,3939 nel recente. Differenza +0,6331, p wild 0,0118, Holm-12 0,1298. Quello con angoli assoluti dà una differenza +0,5125, p 0,07105. Il contrasto standardizzato è un funzionale empirico: non è una media angolare uniforme sul cerchio.

La decomposizione simmetrica della differenza fra medie settoriali **fittate**, nel modello a raggio lineare e angoli quadratici, è:

- cambiamento della composizione osservata di ampiezze, angoli e stato: **+0,8574**;
- cambiamento dei coefficienti della risposta: **+0,4398**;
- somma: +1,2972; differenza osservata: +1,4287; residuo non spiegato: +0,1314.

La componente di composizione ha p wild 0,00005 e Holm-16 0,0008; la componente di risposta p 0,06895 e Holm-16 0,4137. Sono test condizionali alle distribuzioni empiriche fissate e alla continuazione normale. La decomposizione sull'intero campione può estrapolare; entro il supporto comune la composizione resta positiva (+0,5819), ma cambia il bersaglio e aumenta il residuo non spiegato (+0,8175). Non presenterei quindi una percentuale «spiegata dalla composizione» come parametro stabile o causale.

## Chiusura dei claim

**Da mantenere:** associazione positiva fra ampiezza delle sorprese e volatilità bipower anomala in entrambe le epoche; inadeguatezza predittiva della crescita quadratica rispetto alle alternative lineari considerate; differenze di composizione documentate e rilevanti.

**Da ritirare come conclusione acquisita:** «nel 2000–2012 conta soltanto l'informazione azionaria»; «l'ordinamento strutturale MP–CBI si è certamente invertito»; «tutto dipende dalla composizione». Le prime due forme lineari predicono in modo simile e non stabiliscono lo stesso ordinamento con pari precisione.

**Da circoscrivere:** l'eterogeneità settoriale tra epoche è un risultato esplorativo dipendente dalla forma angolare, con un segnale presente in alcune specifiche e un supporto comune ridotto. Il mancato rifiuto non dimostra equivalenza; non era stata dichiarata una soglia economica di equivalenza per questi contrasti. Non occorre inseguire altre specifiche per poter chiudere questa parte del paper con tale limite.

Tutti i test usano 19.999 draw wild per meeting. I CSV contengono anche intervalli pointwise bootstrap-t non ristretto al 95%; questi non sono inversioni del test ristretto e possono dare verdetti diversi in campione finito. I p Holm restano il riferimento per le decisioni entro le famiglie dichiarate. Incertezza su regressori generati, selezione del supporto e target empirico non è integrata. Il calendario USA resta quello ereditato, con coincidenze candidate e non rilasci verificati. Non sono risultati confirmatori o prove di causalità.

## Riproducibilità

Il pacchetto include input evento derivati con SHA256, provenienza, protocollo esplorativo scritto prima dei nuovi confronti tra epoche, sorgenti eseguiti e tutte le tabelle. `Prepare_cross_epoch_inputs.py` ricostruisce gli input dagli archivi aperti; `Run_cross_epoch_checks.py` replica la diagnostica usando gli input inclusi. Non modifica output preesistenti né le guardie del campione protetto. La patch aggiunge il confronto al clone autorizzato e include la precedente correzione funzionale se manca. Nessun commit o push è eseguito.
