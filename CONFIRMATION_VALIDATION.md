# Verifica della preparazione v2, 12 settembre 2026

Base del repository `c224fe07dded3599bfb57f8be23e5e4c2032db53`. Il nuovo codice e' isolato in `confirmation_analysis`; i moduli Python e la specifica v1 non sono modificati. Lo stato v2 e' `draft_not_frozen`. Non e' stata eseguita alcuna regressione o costruzione di outcome evento sul 2000-2012.

**Verifica automatica.** Undici test Python passano. Controllano l'integrazione diretta dei funzionali di cono, il fattore due della base incrociata, il cambio di base con rotazione del dominio, CR1 per combinazioni lineari, code unilaterali firmate, invarianza rispetto al batching del bootstrap, gate di risoluzione, anni 00/12/99 e limite superiore, DST storico, blocco del ponte prima della lettura di outcome pre-2013, audit senza colonne prezzo e distinzione fra finestra GC_PC e conferenza verificata. La sintassi dei due runner shell e' verificata. I self-test MATLAB sono inclusi ma non sono stati eseguiti in questo ambiente; il runner preparatorio li esegue sul Mac quando MATLAB e' disponibile.

**Ponte sul solo campione di generazione.** Build di ingresso `final_resume_20260911_174739_4124`, manifest SHA256 `d7ef6b78ccb6be4283a196da4afe3c55458b25e8147c225b5b595454bf281b85`. Il filtro e' 2013-01-01 / 2025-12-31. Le due fonti sono confrontate sullo stesso campione di 111 meeting. Outcome Bund-only, log BV anomala con continuazione e stato leave-year-out; base grezza a otto colonne, scala PR dei controlli per i futures e degli eventi di generazione per STOXX50E. Bootstrap direzionale con 19.999 repliche.

| Ipotesi | Futures azionario | STOXX50E EA-EMPD |
|---|---:|---:|
| H1, media del cono MP positiva, p wild | 0.00030 | 0.00125 |
| H2, media MP meno media CBI positiva, p wild | 0.28890 | 0.06260 |

Le stime puntuali sono positive. Questi sono risultati di generazione, non conferme sul nuovo campione. La metrica delle due coordinate non e' identica, quindi i coefficienti non si confrontano come effetti nella stessa unita'. H1 non e' il vecchio coefficiente di energia MP ruotata; H2 non e' deducibile dalla non significativita' separata di CBI.

La correlazione fra le coordinate azionarie e' 0.947336, sopra 0.90. La mediana JK con STOXX50E e' 0.550263 e appartiene all'intervallo con futures [0, 1.145027]. Il confronto dei p entro un fattore tre non passa: i rapporti esterno/futures sono 4.166667 per H1 e 0.216684 per H2. Il rapporto fra SD azionaria EA sugli eventi e SD dei futures sui controlli e' 2.497509, fuori [0.7, 1.4]. Il ponte registra quindi il fallback esterno omogeneo come candidato da discutere e lascia `selection_finalized=false`. Nessuna scelta e' presa usando gli outcome 2000-2012.

**Metadati del nuovo periodo.** Il file EA-EMPD gia' disponibile contiene 181 date con 181 finestre GC_PR e 181 GC_PC. OIS1M manca in 13 finestre PR e 7 PC. Il registro conserva 1.448 righe data-radice-fase. Le finestre PC del dataset non sono automaticamente conferenze effettive; calendario e orari devono essere verificati. La copia dei dati disponibile nell'ambiente di sviluppo non contiene i nuovi 164 contratti: l'audit dei loro file e delle sessioni deve essere eseguito sul Mac. Il conteggio zero di questa prova descrive la disponibilita' locale, non l'archivio scaricato dall'autore.

I risultati del ponte e i metadati vengono rigenerati da `Run_confirmation_prepare.sh`. La specifica confermativa, la calibrazione ex ante, la famiglia secondaria con il relativo intervallo e il runner di stima v2 restano da completare prima del freeze.

## Audit di qualita' aggiunto al branch del 12 settembre

L'ultimo inventario fornito dall'autore trova 164 celle attese, 163 con barre,
una cella vuota `fxh11` e dieci celle con copie candidate. Il ramo primario
esclude la duplicazione delle sorgenti. Questi risultati sono metadati del Mac,
non una validazione OHLC effettuata in questo ambiente.

Il nuovo audit di qualita' e' verificato su dati sintetici. I test controllano
griglie esatte e buchi interni, supporto PR, DST storico, OHLC, timestamp duplicati,
volumi nulli senza cancellazione, assenza di look-ahead nella regola degli spike
e nella selezione, priorita' delle sorgenti, hash cambiati e conferenze assenti.
Non vengono costruiti RV/BV o regressori sorpresa sul campione di conferma.
Il dataset grezzo profondo resta sul Mac; questa PR non certifica l'esito del
suo audit, non congela v2 e non implementa ancora calibrazione o stima.

Verifica locale finale: 39 test Python superati (24 conferma/qualita' e 15 v1),
compilazione Python, sintassi dei quattro runner shell e `git diff --check`
superati. I nuovi self-test MATLAB sono inclusi ma non eseguiti qui.
