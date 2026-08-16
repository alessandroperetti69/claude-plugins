# Architettura

## Il problema
Un agente di coding con contesto molto pieno degrada: perde le istruzioni iniziali, ripete lavoro, "dimentica" decisioni. La best practice è tenere il contesto piccolo e persistere lo stato fuori dalla conversazione. Ma in Claude Code una **skill è solo testo**: non può misurare la finestra di contesto né eseguire `/clear`. Servono componenti diversi che collaborano.

## I tre componenti

```mermaid
flowchart LR
  subgraph plugin[plugin cleanloop]
    S[Skill<br/>SKILL.md<br/><i>protocollo</i>]
    H[Hook<br/>hooks.json + scripts/<br/><i>misura, avvisa, guarda</i>]
    R[Runner<br/>cleanloop.sh<br/><i>loop a sessioni fresche</i>]
  end
  subgraph files[stato nel progetto]
    T[TASK.md]
    P[PROGRESS.md]
    C[CLAUDE.md]
    ST[.cleanloop/]
  end
  S -- legge/scrive --> P
  S -- fatti durevoli --> C
  H -- inietta --> S
  H -- last.json, marker --> ST
  R -- claude -p --plugin-dir --> H
  R -- STATUS/ITERATION --> P
  T --> S
```

| Componente | Ruolo | Vincolo che risolve |
|---|---|---|
| **Skill** (`skills/cleanloop/SKILL.md`) | Definisce il *protocollo*: come si fa un checkpoint, come si riprende, cosa va in `PROGRESS.md` e cosa in `CLAUDE.md`. | Il modello sa cosa fare quando gli viene chiesto. |
| **Hook** (`hooks/hooks.json`, `scripts/*.sh`) | Misurano il contesto a ogni tool call e iniettano l'istruzione di checkpoint; reiniettano lo stato all'avvio; proteggono lo stato in compattazione; impediscono di chiudere un'iterazione senza checkpoint. | La skill non può misurare: lo fa l'harness. |
| **Runner** (`scripts/cleanloop.sh`) | Esegue `claude -p` in loop, una sessione nuova per iterazione, con condizioni di stop. | La skill non può eseguire `/clear`: la pulizia è un nuovo processo. |

## Come si misura il contesto
Ogni hook riceve `transcript_path` (il JSONL della sessione). L'ultimo messaggio di tipo `assistant` contiene `message.usage`; i token in contesto al momento della chiamata sono:

```
used = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
pct  = used / context_window * 100
```
La finestra è `CLEANLOOP_CONTEXT_WINDOW` se impostata, altrimenti 1M se il modello in `~/.claude/settings.json` contiene `[1m]`, altrimenti 200k. È la stessa grandezza che la statusline riceve come `context_window.used_percentage`, ma calcolata dal transcript perché in modalità `-p` la statusline non gira.

## Flusso di un'iterazione in modalità loop

```mermaid
sequenceDiagram
  participant U as cleanloop.sh
  participant CC as claude -p (nuovo processo)
  participant SS as SessionStart hook
  participant M as modello
  participant PG as PostToolUse hook
  participant SG as Stop hook
  U->>U: STATUS è DONE/BLOCKED? → esci
  U->>U: checksum(PROGRESS.md) prima
  U->>CC: --plugin-dir, --append-system-prompt-file, --autocompact, prompt "iterazione i"
  CC->>SS: source=startup
  SS-->>M: additionalContext = regole + TASK.md + PROGRESS.md; salva checksum iniziale
  loop ogni tool call
    M->>PG: (transcript_path)
    PG->>PG: pct = usage / window
    alt pct ≥ HARD (una volta)
      PG-->>M: "FERMATI ORA: checkpoint e termina"
    else pct ≥ THRESHOLD (una volta, poi promemoria)
      PG-->>M: "chiudi il sotto-task, checkpoint, termina"
    end
  end
  M->>SG: fine turno
  alt PROGRESS.md invariato
    SG-->>M: decision=block, "aggiorna PROGRESS.md" (una sola volta)
  else modificato
    SG-->>CC: ok
  end
  CC-->>U: exit
  U->>U: checksum dopo → progresso o stallo++
```

## Flusso in sessione interattiva

```mermaid
stateDiagram-v2
  [*] --> Lavoro: /cleanloop (SessionStart inietta PROGRESS.md)
  Lavoro --> Lavoro: tool call, pct < soglia
  Lavoro --> Checkpoint: PostToolUse pct ≥ soglia
  Checkpoint --> AttesaClear: PROGRESS.md aggiornato, "esegui /clear e /cleanloop"
  AttesaClear --> Lavoro: utente /clear + /cleanloop (SessionStart source=clear)
  AttesaClear --> Lavoro: utente /compact (PreCompact protegge lo stato)
  Lavoro --> [*]: STATUS DONE
```

## Decisioni di design

**Fresh session invece di compattazione.** `/compact` produce un riassunto scritto dal modello: opaco, non verificabile, e il contesto non è mai davvero pulito. Un nuovo processo `claude -p` che rilegge `PROGRESS.md` è deterministico e ispezionabile (il file *è* il riassunto). La compattazione resta solo come rete di sicurezza (`--autocompact` oltre la soglia dura, `PreCompact` che protegge lo stato).

**Stato nei file, con un formato fisso.** `PROGRESS.md` ha sezioni obbligatorie e un limite di lunghezza (~40 righe) perché viene reiniettato integralmente a ogni iterazione: se crescesse, mangerebbe il budget di contesto che si vuole proteggere. `CLAUDE.md` riceve solo fatti durevoli per lo stesso motivo (viene caricato in *ogni* sessione).

**Hook inerti per default.** Il plugin è installato a livello utente ma agisce solo dove esiste `.cleanloop/enabled` (o `CLEANLOOP_ACTIVE=1`): nessun effetto collaterale negli altri progetti, costo di attivazione ~220 token per sessione.

**Soglia morbida + soglia dura + promemoria.** Un unico avviso può essere ignorato "perché manca poco". Il pattern morbida (chiudi il sotto-task) / dura (fermati) / promemoria periodico è la stessa struttura di un buon backpressure: graduale, ma con un limite.

**Stop hook solo in loop.** In sessione interattiva bloccare la fine turno sarebbe invadente; in `-p` è l'unica garanzia che un'iterazione produca un checkpoint. Blocca una sola volta (`stop_hook_active`) per non incastrare mai il loop.

**Confronto per checksum, non per mtime.** Il runner e lo Stop hook rilevano il progresso confrontando l'hash di `PROGRESS.md`: un `touch` non conta, la risoluzione al secondo dell'mtime non crea falsi negativi.

**Guardie del loop.** Stallo (N iterazioni senza modifiche), massimo iterazioni, budget per iterazione, `BLOCKED` esplicito: un loop autonomo deve poter fallire in modo pulito, non girare all'infinito.

## Limiti noti
- La misura del contesto è aggiornata alla tool call precedente: tra due tool call il modello può generare testo lungo senza che l'hook lo veda.
- La percentuale dipende dalla finestra dichiarata: se il modello del loop ha una finestra diversa da quella in `settings.json`, va impostata `CLEANLOOP_CONTEXT_WINDOW`.
- In interattivo il passaggio `/clear` è manuale (limite della piattaforma).
- `bash`, `jq`, `md5`/`md5sum` sono richiesti; testato su macOS, atteso funzionante su Linux.
