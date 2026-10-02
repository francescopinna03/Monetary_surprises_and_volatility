# Piano di conferma sul campione 2000–2012

**Progetto:** State-Dependent Transmission of ECB Monetary Surprises
**Data:** 12 settembre 2026
**Stato:** bozza di protocollo, da congelare prima di qualunque stima sul 2000–2012

---

## 0. Principi

Il piano ha un solo scopo: trasformare le 181 riunioni del 2000–2012 in un campione di conferma valido. Un campione è di conferma se tre condizioni valgono insieme.

1. Nessuna stima viene eseguita su di esso prima del congelamento della specifica.
2. Le ipotesi da confermare sono scritte in forma eseguibile, con direzione, famiglia, numero di repliche e margini, e derivano dal solo campione di generazione 2013–2025.
3. Ogni scelta che il campione nuovo impone — sorgente della coordinata azionaria, gestione dei buchi OIS, scala delle variabili — è dichiarata prima e validata sul campione di generazione, mai sul campione di conferma.

Il principio inferenziale che governa la sezione sulla rotazione è questo: **l'inferenza confermativa si fa su funzionali invarianti per rotazione; la rotazione serve a interpretare, non a testare.** Le ragioni sono nella Sezione 3.

---

## 1. Campioni e registro

### 1.1 Definizioni

| Campione | Riunioni | Ruolo | Vincoli |
|---|---|---|---|
| Generazione | 2013–2025, ~110 | Ha prodotto le ipotesi. Serve per la validazione ponte (§3.4) e per le sensibilità pooled | Già visto; non produce conferme |
| Conferma | 2000–2012, 181 | Stima confermativa | Mai visto. Nessuna stima prima del freeze v2 |
| Pooled | 2000–2025, ~291 | Solo descrittivo e per le frontiere di potenza | Non produce conferme |

Il 1999 è escluso: i contratti con scadenza 1999 non esistono nell'archivio Barchart. La riunione del 2 dicembre 1999 cade in zona rollover del contratto marzo 2000 e sarà esclusa dal pannello di qualità, non a mano.

### 1.2 Registro eventi

Il registro si costruisce da EA-EMPD, colonne `Date_time` delle righe `GC_PR` e `GC_PC`. Dal 2000 al 2012 il comunicato è sempre alle 13:45 CET e la conferenza alle 14:30 CET. Il registro va incrociato con il calendario ECB pubblicato, riunione per riunione. Ogni discrepanza si annota, non si corregge in silenzio.

Il registro include ogni riunione, ogni radice e ogni fase anche quando manca il contratto o la sorpresa, come nel protocollo v1. Aggiunge tre colonne nuove:

- `equity_source`: `fx_futures` se disponibile la radice fx nella fase, altrimenti `ea_empd_stoxx50e`;
- `ois1m_available`: vero o falso, dalla colonna `OIS_1M`;
- `era`: `2000-2007`, `2008-2012`, `2013-2025`, per le sensibilità per epoca.

### 1.3 Copertura attesa

Dalla lettura di EA-EMPD: 24 riunioni nel 2000, 24 nel 2001, 133 dal 2002 al 2012. `STOXX50E` e `OIS_1Y` sono completi su tutte. `OIS_1M` manca in 7 riunioni del 2000, 2 del 2001, 6 nel 2001–2012. Il campione effettivo di ciascun modello lo fissa il registro di campione prodotto dalla stima, con le esclusioni per modello, outcome e indicatore. Non si impone un N artificialmente comune.

---

## 2. Dati

### 2.1 Barchart

164 file: le sedici scadenze trimestrali di ciascun anno dal 2000 al 2012 per `gg`, `hf`, `hr` (156 file) e le scadenze 2011–2012 per `fx` (8 file). Ogni file porta la vita intera del contratto; il trimestre front-month è quello utilizzabile. I giorni non-evento degli stessi file forniscono il pool di controllo: circa 3.200 giornate-radice aggiuntive per radice, nessun download separato.

### 2.2 EA-EMPD

Colonne usate, tutte per fase (`GC_PR`, `GC_PC`):

- `OIS_1M`, `OIS_3M`, `OIS_6M`, `OIS_1Y`: coordinata di policy nei rami esterni;
- `STOXX50E`: coordinata azionaria quando fx non è disponibile (tutto il 2000–giugno 2011, e come ramo di robustness ovunque).

Le finestre di EA-EMPD sono quelle del dataset: per il comunicato chiudono circa a +15/+25 minuti, per la conferenza circa a +70/+80. La conseguenza per la fase PC è nella §3.8.

### 2.3 Rilasci USA

Costruire `Raw/Certification/us_releases.csv` con `release_id,timestamp_utc,source_url` dagli archivi BLS e DoL per il 2000–2026. Le richieste di sussidio escono ogni giovedì alle 8:30 ET; tutte le riunioni fino al 2014 sono di giovedì. Fino al 2022 le 8:30 ET cadono alle 14:30 di Francoforte, cioè esattamente all'apertura della conferenza. È un'esposizione costante, presente identicamente nei controlli del giovedì: il matching per giorno la neutralizza in media. Il file verificato trasforma lo status da `candidate_screen_only` a `verified`, e permette la sensibilità di esclusione sul solo ramo PR, dove l'esposizione è variabile.

---

## 3. Uso della rotazione MP/CBI

Questa è la sezione centrale. Fissa cosa la rotazione è, cosa dipende da essa, cosa no, da dove vengono le sue coordinate nei due campioni, e su quali oggetti si fa inferenza confermativa.

### 3.1 Oggetti

Per ogni riunione e fase si osserva il **vettore delle sorprese osservate**, di dimensione 2:

- la coordinata di policy, scalare, positiva quando i tassi salgono nella finestra;
- la coordinata azionaria, scalare, positiva quando l'indice sale nella finestra.

Lo denoto x_{e,p} = (u_{e,p}, z_{e,p})', come nella nota Step 22–28. Entrambe le coordinate sono espresse in deviazioni standard, con la scala fissata secondo la §3.5.

La **matrice di rotazione**, di dimensione 2×2, è R(θ), con θ un angolo. Il vettore ruotato è η_{e,p}(θ) = R(θ)' x_{e,p}, le cui componenti si chiamano MP e CBI. Le restrizioni di segno di Jarociński–Karadi definiscono l'**insieme identificato** Θ_p: l'intervallo di angoli per cui la componente MP muove tassi e azionario in direzioni opposte e la componente CBI li muove nella stessa direzione. Il codice esistente (`JK_median_rotation.m`) stima Θ_p e ne prende la mediana θ_50; l'audit usa i quantili 0,1 / 0,25 / 0,5 / 0,75 / 0,9 dell'insieme.

Il **modello di risposta** è la superficie quadratica dei livelli precedenti. Per l'outcome y_{i,e,p}, cioè il log della BV anomala dell'asset i nella fase p:

    y_{i,e,p} = α_p + Γ_p' s_e + λ_i + x_{e,p}' A_p(s_e) x_{e,p} + errore,    A_p(s) = A_{p,0} + s · A_{p,1}.

A_{p,0} è la **matrice simmetrica 2×2 della superficie a stato nullo**, con entrate a_{11} (curvatura lungo u), a_{22} (curvatura lungo z), a_{12} (termine incrociato). A_{p,1} è la matrice della modulazione da parte dello stato s_e, lo stato pre-annuncio standardizzato sui controlli. Tutto è stimato nella **base quadratica grezza** (u², z², 2uz), senza rotazione.

### 3.2 Cosa è invariante e cosa no

Per la Proposizione di invarianza rotazionale già nella nota, per ogni θ esiste B = R(θ)' A R(θ) tale che x'Ax = η'Bη. Quindi:

**Invarianti per rotazione** (parametri del modello, non della rappresentazione):

- la superficie stimata e i suoi valori predetti;
- le tre entrate di A nella base grezza, a_{11}, a_{12}, a_{22};
- traccia, determinante, autovalori e autovettori di A;
- ogni media della forma quadratica su un cono definito dai **segni delle coordinate grezze**, perché i coni MP e CBI sono definiti da sign(u) e sign(z), non da θ.

**Non invarianti** (parametri della rappresentazione):

- il coefficiente etichettato "energia MP", cioè l'entrata (1,1) di B(θ);
- il coefficiente "energia CBI", entrata (2,2) di B(θ);
- il loro contrasto a θ fissato.

Il risultato del campione di generazione — energia MP positiva, wild 0,003, stabile sulla griglia — è un enunciato su B(θ) lungo cinque θ. È robusto nelle sensibilità eseguite, ma il suo p dipende da θ e la famiglia da 896 test non poteva confermarlo. Il piano lo riformula come enunciato su A.

### 3.3 Le due ipotesi confermative, in forma invariante

Si definisce la **curvatura media di cono**: la media della forma quadratica d'Ad lungo le direzioni unitarie d che cadono nel cono, con peso uniforme sull'angolo. Poiché la forma è pari in d, i coni sono coppie di quadranti opposti: il cono MP è {u>0, z<0} ∪ {u<0, z>0}, il cono CBI è {u>0, z>0} ∪ {u<0, z<0}.

Con d(φ) = (cos φ, sin φ), la media sul cono MP è l'integrale su φ ∈ (−π/2, 0) diviso π/2. Il calcolo dà, in forma chiusa:

    ā_MP  = (a_{11} + a_{22})/2 − (2/π) · a_{12}
    ā_CBI = (a_{11} + a_{22})/2 + (2/π) · a_{12}
    ā_MP − ā_CBI = −(4/π) · a_{12}

Le due ipotesi confermative sono:

**H1 (energia nel settore MP alza la BV anomala del comunicato):** ā_MP > 0 nella fase PR, outcome Bund-only.

**H2 (il settore MP conta più del settore CBI):** ā_MP − ā_CBI > 0 nella fase PR, outcome Bund-only. Equivale a a_{12} < 0: la superficie è più alta dove tassi e azionario si muovono in direzioni opposte.

Entrambe sono combinazioni lineari dei coefficienti della base grezza: si testano con lo stesso wild cluster per riunione già in `models.py`, senza stimare alcun θ. Sono direzionali, perché la direzione è stata generata sul 2013–2025: i p sono unilaterali e la cosa è dichiarata nel freeze. Formano una famiglia di due test con Holm.

Il contrasto esplicito MP−CBI, che il rapporto dell'11 settembre segnalava come mai eseguito, è H2. È anche il punto in cui il vecchio "CBI non significativo" diventa un enunciato verificabile.

### 3.4 Sorgenti delle coordinate e validazione ponte

Nel campione di generazione la coordinata di policy è il rendimento log dello Schatz cambiato di segno sulla finestra della fase, e la coordinata azionaria è il rendimento netto di fx sulla stessa finestra. Entrambe chiudono con l'outcome: sono la coppia **allineata**.

Nel campione di conferma la coordinata di policy resta lo Schatz allineato — `hf` esiste dal marzo 2000. La coordinata azionaria no: fx esiste da giugno 2011. Per il 2000–giugno 2011 l'unica coordinata azionaria è `STOXX50E` di EA-EMPD, misurata sulla finestra del comunicato di EA-EMPD, che chiude tra +15 e +25 minuti. Per la fase PR è quindi **quasi allineata** con l'outcome (PR, PR+25]: non contiene informazione successiva all'outcome.

Sostituire fx con STOXX50E cambia la coordinata su cui H1 e H2 sono state generate. La sostituzione va validata sul campione dove esistono entrambe, cioè giugno 2011–2025. Questa **validazione ponte** si esegue prima del freeze v2, sul solo campione di generazione più i 18 mesi 2011H2–2012, e prevede quattro controlli con soglie dichiarate:

1. correlazione fra z da fx e z da STOXX50E nella fase PR, riunione per riunione: soglia 0,90;
2. sovrapposizione degli insiemi identificati Θ_PR stimati con le due coordinate: la mediana θ_50 con STOXX50E deve cadere dentro Θ_PR stimato con fx;
3. replica di ā_MP e a_{12} sul 2013–2025 con STOXX50E al posto di fx: stesso segno, p wild entro un fattore 3 del valore con fx;
4. stabilità della scala: la deviazione standard di STOXX50E sulle riunioni 2013–2025 confrontata con quella di fx sui controlli, rapporto entro [0,7; 1,4].

Se i quattro controlli passano, STOXX50E è la coordinata azionaria dichiarata per il 2000–2011H1, e fx per il 2011H2–2012. Se il controllo 1 o 3 fallisce, il fallback dichiarato è usare STOXX50E per **tutto** il 2000–2012, così che la coordinata sia omogenea dentro il campione di conferma, e riportare la discrepanza con fx come limite. Il fallback si sceglie ora, non dopo.

### 3.5 Scala delle coordinate

La scala decide i coni: una coordinata più compressa restringe il suo cono. Regola:

- coordinata di policy: deviazione standard dello Schatz allineato sui controlli PR pooled, senza centratura, come nel v1; i controlli esistono per tutto il 2000–2012;
- coordinata azionaria da fx: deviazione standard sui controlli, come nel v1;
- coordinata azionaria da STOXX50E: non esistono controlli, EA-EMPD ha solo giorni-evento. Si standardizza sulle riunioni `GC_PR` del **campione di conferma**, senza centratura. Usa dati evento ma non l'outcome, e non viene aggiornata dopo la stima. La validazione ponte controllo 4 verifica che questa scala sia comparabile a quella sui controlli.

### 3.6 Ruolo residuo di θ

Dopo le §3.2–3.3 la rotazione ha tre usi, tutti descrittivi:

- **lettura**: le tabelle riportano B(θ_50) accanto ad A, perché "energia MP" è la lingua della letteratura; la didascalia dichiara che B dipende da θ e A no;
- **audit**: la griglia a cinque θ resta come sensibilità, senza Holm e senza pretesa confermativa;
- **coerenza con i coni**: si riporta se l'autovettore principale di A cade nel cono MP e se Θ_PR di conferma si sovrappone a Θ_PR di generazione. Sono diagnostici, non test.

Nessun p confermativo viene calcolato a un θ fissato.

### 3.7 Modulazione da parte dello stato

A_{p,1} è la matrice della dipendenza dallo stato. Nel campione di generazione la modulazione MP × stato era instabile (0,054 pieno, 0,304 senza i primi 5). Non entra nella famiglia primaria. Si riporta come **ipotesi secondaria dichiarata**, in forma invariante: ā_MP calcolata su A_{p,1}, con p wild bilaterale. È la versione di secondo ordine della domanda originaria, e il suo esito atteso è discusso nella §6.

### 3.8 La fase PC

Per la conferenza, STOXX50E di EA-EMPD chiude 25–35 minuti dopo l'outcome (PC, PC+45]: è **ex post**, come già stabilito. Prima di giugno 2011 non esiste una coordinata azionaria allineata per la PC. Conseguenze:

- l'eterogeneità PR–PC con indicatori allineati è replicabile solo su 2011H2–2012, circa 18 riunioni: non è confermabile fuori campione. Va scritto così;
- sul 2000–2011H1 la superficie PC si stima con coordinate EA-EMPD come **ramo ex post**, con la stessa etichetta del v1, a solo scopo descrittivo;
- H1 e H2 sono definite sulla sola fase PR proprio per questo.

---

## 4. Modifiche alla pipeline, stage per stage

I nomi sono quelli dei moduli nel repository.

### 4.1 Ingestione e audit grezzo — `Audit_Barchart.m`, `Clean_raw_files.m`, `File_sha256.m`

- Estendere l'inventario ai 164 file; hash sha256 per ciascuno nel manifest dati.
- `Contract_event_day.m`: il suffisso a due cifre `00`–`12` va mappato a 2000–2012 in modo esplicito; aggiungere un test che rifiuti qualunque anno inferiore al 1999 o superiore all'anno corrente.
- Aggiungere all'audit la **lunghezza di sessione per file**: barre per giorno, primo e ultimo timestamp intraday. Nel 2000 la giornata è di 128–132 barre, nel 2006 di 169. La tabella va nel manifest.
- Spike e barre a basso volume: stessa regola del v1 (rimozione dello spike isolato, flag senza cancellazione).

### 4.2 Certificazione di orologio e bar-label — `Audit_timezone_provenance.m`, `Audit_bar_label_convention.m`, `Event_time_alignment_audit.m`, `Run_time_alignment_smoke.m`

- Ri-certificare `interval_start` → `interval_end_utc` sull'archivio profondo: lo stesso test del v1 su almeno un file per radice e per triennio (2000, 2003, 2006, 2009, 2012).
- Estendere i self-test DST. Fino al 2006 l'ora legale USA iniziava la prima domenica di aprile e finiva l'ultima di ottobre; dal 2007 seconda domenica di marzo e prima di novembre. L'Europa è invariata: ultima domenica di marzo e di ottobre. Nelle settimane di sfasamento l'offset CT–Francoforte non è 7 ore. Due esempi con riunione BCE dentro lo sfasamento, da mettere nel self-test: **1 aprile 2004** (Europa già in ora legale, USA no: 8 ore) e **4 novembre 2004** (Europa già tornata, USA no: 6 ore). La conversione IANA `America/Chicago` li gestisce; il test serve a provare che nessuna parte del codice assume un offset fisso.
- `Event_time_alignment_audit.m`: verificare per ogni riunione 2000–2012 che il picco di volume del Bund cada nelle barre 13:45–13:55 CET. È il test empirico di allineamento che abbiamo già fatto a mano su dieci riunioni.

### 4.3 Finestre e pannelli — `Event_windows.m`, `Phase_window_construction.m`, `Press_release_panel.m`, `PR_bar_panel.m`

- Finestre come nel protocollo v1: PR (PR, PR+25], PC (PC, PC+45], stato (PR−60, PR−5], previsione della continuazione pre-PR per PR e (PC−25, PC−5] per PC. Nessun parametro cambia.
- Aggiungere il **gate di sessione**: ogni finestra di controllo deve cadere interamente dentro la sessione del giorno; le giornate che non lo consentono vengono escluse dal pool di controllo con motivo registrato. Nel 2000 la finestra di stato (12:45, 13:40] CET è dentro sessione; il gate serve ai casi di apertura ritardata o chiusura anticipata.
- Un solo estrattore di barre per RV e BV, come già corretto nel v1.

### 4.4 Selezione del contratto — `Contract_event_day.m`, `preferred_contracts.csv`

- Stessa regola v1: completezza e copertura pre-PR, poi volume pre-PR, poi nome file; nessuna variabile post-PR.
- Nei primi anni la selezione fra contratto in scadenza e successivo intorno al roll di marzo/giugno/settembre/dicembre è più delicata perché il volume migra in pochi giorni; il ranking pre-PR la gestisce, ma la tabella dei contratti scelti per riunione va pubblicata nel manifest.

### 4.5 Lettura di EA-EMPD — `Locate_ea_policy_dataset.m`, `Read_ea_policy_window.m`, `Require_surprise_source_manifest.m`

- Estendere la lettura al 2000–2012 per `GC_PR` e `GC_PC`.
- Aggiungere `STOXX50E` come colonna letta e propagata nel registro, con `equity_source` per riunione e fase.
- Gestione di `OIS_1M` mancante: nessun riempimento. Il ramo PC1 EA-EMPD richiede tutte e quattro le maturità e perde quelle riunioni; il ramo `OIS_1Y` non ne perde nessuna. Entrambi restano rami esterni; il primario è lo Schatz allineato.

### 4.6 Componenti dello shock — `Build_JK_shock_components.m`, `JK_median_rotation.m`, `Apply_JK_shock_fit.m`

- `Build_JK_shock_components.m`: aggiungere la costruzione della coppia (u, z) con z da `STOXX50E` quando `equity_source = ea_empd_stoxx50e`, con la scala della §3.5.
- `JK_median_rotation.m`: stimare Θ_p e θ_50 separatamente sul campione di generazione e su quello di conferma; salvare entrambi; non usare mai una rotazione stimata sul pooled per un test.
- Nuovo modulo `Cone_functionals.m` (nome libero da collisioni): riceve A nella base grezza e restituisce ā_MP, ā_CBI e la differenza con le formule della §3.3; include un self-test numerico contro l'integrazione diretta su una griglia di angoli.

### 4.7 Controfattuale — `Announcement_counterfactual.m`, `Announcement_phase_counterfactual.m`, `Announcement_counterfactual_validation.m`

- Il modello di continuazione normale si stima per fold annuale sui soli controlli, come nel v1. Con 13 anni in più il pool cresce di circa 3.200 giornate-radice per radice; nessuna modifica di forma.
- Il matching per giorno della settimana è banale nel 2000–2014 perché tutte le riunioni sono di giovedì: i controlli sono i giovedì non-BCE.
- La standardizzazione dello stato usa solo i controlli, per fold.
- Aggiungere il flag `us_release_verified` dal file della §2.3.

### 4.8 Batteria storica MATLAB — Step 9–21, `Run_pipeline.m`

- Non è l'entry point della conferma. Si rilancia solo per rigenerare manifest e finestre canoniche sull'archivio esteso e per il rerun ausiliario `Run_final_matlab_checks` (finestre, shrinkage con 1-SE corretta, gate 28).
- I moduli con outcome a quattro radici restano etichettati come sensibilità.

### 4.9 Step 22–25 — `Phase_component_contrasts.m`, `Invariant_phase_attribution.m`

- Il contrasto di superficie PR–PC con indicatori allineati si calcola sul 2011H2–2025 pooled a solo scopo descrittivo, con l'etichetta "non confermato fuori campione". Sul 2000–2011H1 esiste solo il ramo ex post.
- La geometria invariante (Rayleigh su Σ^{1/2} ΔA Σ^{1/2}) resta descrittiva.

### 4.10 Step 26–27 — `Long_horizon_phase_attribution.m`, `Rank_one_feasibility.m`, `Dynamic_jump_frontier.m`

- Nessuna riesecuzione confermativa. Il 27B va riportato con il dato di collinearità del null (96,96% del salto spiegato dalla base) come proprietà del disegno. Se si vuole un dato aggiornato, si ricalibra la potenza a N=291 per la sola documentazione, senza stimare l'operatore.

### 4.11 Step 28 — `Run_step28.m`, `Run_step28_gates.m`, `Step28_sample_size_calibration.m`

- Rieseguire la sola **calibrazione outcome-free** con la griglia estesa fino a G=300, per registrare dove si colloca N=291 rispetto ai criteri. La diagnostica esplorativa collocava il passaggio del solo criterio di rango a 300 e quello congiunto a 500. L'esito atteso è che il criterio di proiettore resti non soddisfatto: lo Step 28 resta bloccato, e il numero aggiornato entra nella sezione dei limiti. Nessuna stima SBB.

---

## 5. Specifica v2 del runner Python

Nuovo build `final_analysis_v2`, nuova `final_analysis_spec_v2.json`. La v1 ha visto il 2013–2025 e non tocca il 2000–2012.

### 5.1 Ordine di esecuzione

1. **Ponte** (`bridge` mode, nuova): esegue i quattro controlli della §3.4 sul 2011H2–2025 e scrive `bridge_decision.json` con l'esito e la coordinata azionaria dichiarata. Vieta il passo successivo se il file manca.
2. **Calibrazione ex ante** (`calibrate`, nuova): con la matrice di disegno del campione di conferma e i soli controlli — nessun outcome evento — calcola la potenza di H1 e H2 per iniezione di segnale e il floor R²₈₀ del ramo di sufficienza. Scrive i margini nella spec. Usa il limite inferiore di Wilson come nel v1.
3. **Freeze**: hash di codice, spec, dati, tabelle; `prior_results_seen=true` per il 2013–2025 e `false` per il 2000–2012, entrambi nel manifest.
4. **Estimate** sul solo campione di conferma.
5. **Estimate pooled** descrittivo, in una directory separata, etichettato.

### 5.2 Famiglie

| Famiglia | Test | Correzione | Repliche |
|---|---|---|---|
| `primary_confirmation` | H1: ā_MP > 0; H2: ā_MP − ā_CBI > 0. Fase PR, Bund-only, log BV anomala, stato nullo | Holm su 2, unilaterali | B = 19.999 |
| `secondary_declared` | modulazione ā_MP(A₁) bilaterale; interazione scalare firmata e assoluta; intervallo di sufficienza; H1 e H2 su RV; H1 e H2 per epoca 2000–2007 / 2008–2012 | Holm dentro la famiglia, riportati come secondari | B = 19.999 |
| `sensitivity_descriptive` | griglia θ, leave-top-K, quattro radici, rami OIS/PC1 EA-EMPD, screen USA, PC ex post | nessuna; nessun claim | B = 999 |

Il gate di risoluzione: 1/(B+1) ≤ 0,05/m per ogni famiglia con claim; con B = 19.999 e m = 2 la soglia di Holm è 0,025 e il p minimo raggiungibile 0,00005. Il gate è meccanico nel freeze e blocca il build se violato.

### 5.3 Livello 1

- Ramo di media: come v1, sorpresa OIS1M/10 firmata e assoluta; sul 2000–2001 le riunioni senza `OIS_1M` cadono; sensibilità con `OIS_1Y`.
- Ramo di sufficienza: blocco storico su `OIS_1Y` (lag-1, media dei tre precedenti) perché completo; `OIS_1M` come sensibilità. Il margine di precisione non è più 0,02: è il valore che la calibrazione del §5.1 restituisce come raggiungibile a potenza 0,80. La regola finita resta: bound sotto il margine e potenza adeguata a quella scala.

### 5.4 Inferenza

Wild cluster per riunione con null ristretto imposto, segni Rademacher comuni ad asset e fasi della riunione, CR1, plus-one, come v1. I p restano **condizionati** agli indicatori misurati e al controfattuale stimato: il manifest lo dichiara.

---

## 6. Cosa aspettarsi

L'aritmetica seguente usa lo scaling 1/√N degli errori standard e 1/N dei partial R² rilevabili; è un'attesa, non una promessa.

**H1.** Sul 2013–2025 l'energia MP aveva wild 0,003 a 110 riunioni, cioè circa t ≈ 3. Se l'effetto ha la stessa ampiezza nel 2000–2012, a 181 riunioni ci si aspetta t ≈ 3,8 e p unilaterale dell'ordine di 10⁻⁴. Sul pooled a 291, t ≈ 4,9. H1 ha buone probabilità di conferma **se l'effetto è stabile nell'epoca**; il rischio principale è l'eterogeneità: il 2000–2007 non ha forward guidance né acquisti, e la composizione MP/CBI può essere diversa. La sensibilità per epoca è lì per questo.

**H2.** Mai testata: la sua potenza la fissa la calibrazione. Un ordine di grandezza: se CBI è nullo con errore standard simile a MP, il contrasto ha t ≈ t_MP/√2, cioè circa 2,1 a 110 e 2,7 a 181, p unilaterale intorno a 0,004. Meno certo di H1 e più informativo.

**Modulazione da stato.** A 110 riunioni era instabile e cambiava segno al trimming. Con 181 riunioni la banda si restringe di un fattore 0,78; se il vero effetto è vicino a zero, l'esito atteso è un nullo più stretto. È l'esito più utile per la domanda originaria: un intervallo che esclude modulazioni economicamente grandi.

**Sufficienza.** Il floor a potenza 0,80 era 0,20 a 103 riunioni. Ci si aspetta circa 0,11 a 181 e 0,07 a 291. Non si arriva a 0,02: la domanda resta un intervallo, ma un intervallo di ampiezza dimezzata. Va scritta così, e la calibrazione ex ante fissa il numero prima della stima.

**Eterogeneità PR–PC.** Non confermabile fuori campione per assenza di fx prima del 2011. Sul pooled 2011H2–2025 il guadagno di potenza è marginale (da 114 a circa 130 riunioni). Resta suggestiva.

**Step 28.** N = 291 resta sotto il fabbisogno congiunto di ~500 e al limite del solo criterio di rango. Rimane un risultato di disegno.

### 6.1 Albero decisionale dichiarato

- H1 e H2 confermate: il paper ha un risultato empirico forte, generato e confermato su campioni disgiunti, con i nulli e le frontiere come seconda parte.
- H1 confermata, H2 no: l'energia d'annuncio conta ma la composizione MP/CBI non è separabile; il paper si concentra sul primo ordine e dichiara il secondo come non stabilito.
- H1 non confermata: eterogeneità d'epoca come lettura principale, con la sensibilità 2000–2007 / 2008–2012 a supporto; il paper resta l'architettura del Binario A, con la mancata replica come risultato.

Nessuno dei tre esiti richiede una nuova specificazione sul campione di conferma. Se ne serve una, il campione ha smesso di essere di conferma.

---

## 7. Sequenza operativa

| Settimana | Attività | Output |
|---|---|---|
| 1 | Download 164 file; audit grezzo; registro 2000–2012 da EA-EMPD; calendario USA verificato | manifest dati v2, `event_registry_v2.csv`, `us_releases.csv` |
| 1–2 | Ri-certificazione orologio e bar-label sull'archivio profondo; self-test DST 2004; audit di allineamento per riunione | manifest di certificazione estesi |
| 2 | Finestre, pannelli, contratti preferiti, controfattuale su tutto il 2000–2025; nessuna stima di H1/H2 | pannelli e pool di controllo |
| 2 | Validazione ponte su 2011H2–2025 | `bridge_decision.json` |
| 3 | Calibrazione ex ante; scrittura e freeze della spec v2 | `final_analysis_v2` congelato |
| 3 | Estimate sul campione di conferma; estimate pooled descrittivo | tabelle v2 |
| 4–6 | Scrittura; Step 28 ricalibrato per la sezione limiti; rerun MATLAB ausiliario | bozza del paper |

Due vincoli di sequenza, non negoziabili: la validazione ponte precede il freeze, e il freeze precede qualsiasi lettura di un outcome del 2000–2012 — compreso un grafico.
