# Test technique — Développeur·se Intégrations & Migration de données

Merci de l'intérêt que vous portez au poste.

Ce test reproduit le quotidien du poste : un nouveau client arrive chez nous et
souhaite retrouver dans Baqio les données de son ancien logiciel. Nous
fournissons ce que nous recevons réellement dans ces situations, et le travail
consiste à les faire entrer proprement en base.

Un collègue a commencé la reprise avant de passer à autre chose.
**Le code existant fonctionne sur un extrait simplifié des fichiers, mais pas
sur les fichiers réels du client.** Il est incomplet et il contient des
erreurs. L'objectif est donc autant de le corriger et de le compléter que
d'écrire du nouveau code.

---

## Temps et rendu

- Une semaine pour nous rendre le sujet, à faire quand cela vous arrange.
- Rendu avec un historique de commits lisible.
- Nous enchaînons sur un entretien d'environ une heure pendant lequel nous
  parcourons votre code ensemble. Le débrief compte autant que le code.

---

## Questions

Si un point métier vous bloque, vous pouvez écrire à quentin@baqio.com.

En situation réelle, ces questions iraient au client : nous y répondrons comme
il le ferait. Les choix techniques, en revanche, vous appartiennent — nous en
discuterons lors de l'entretien.

---

## Ce que nous évaluons

La justesse des données en base, ce que vous faites des données douteuses, la
traçabilité et la lisibilité.

Le point le plus important : **une erreur silencieuse est pire qu'un rejet
explicite**. Un client qui découvre trois mois plus tard que 40 de ses tarifs
sont faux, c'est un incident. Un rapport qui dit « 12 lignes non importées,
voici lesquelles et pourquoi », c'est un échange de cinq minutes.

---

## Les fichiers du client

Le client quitte **CaveGest 4.2**, un logiciel installé en local qu'il utilise
depuis 2011. Son prestataire lui a sorti deux exports, dans `data/` : ses
clients, et son catalogue avec ses grilles tarifaires.

---

## Le travail attendu

Les données des deux exports doivent se retrouver en base, justes, et la
reprise doit pouvoir être relancée sans dégât.

Deux importeurs existent et sont faux : `Customer::Import::Cavegest` et
`ProductPrice::Import::Cavegest`. `Importer::Audit` est vide : il doit porter
les contrôles qui permettent d'affirmer au client que sa reprise est juste,
et nous les attendons calculés depuis la base.

`lib/migration_report.rb` collecte ce qui s'est passé pendant l'import. À la
fin d'une reprise, nous devons pouvoir dire combien d'enregistrements ont été
créés, ce qui a été rejeté et pourquoi, et ce qui est passé mais mérite une
vérification humaine. La forme est libre ; la personne qui lit ce rapport n'est
pas développeuse.

---

## Notes de reprise

Ajoutez une courte section « Notes de reprise » à la fin de votre README, ou
dans un fichier poussé sur le repo. Nous y cherchons ce qu'un collègue
écrirait avant de partir en week-end :

- ce que vous avez décidé sur les cas où les fichiers ne tranchaient pas ;
- ce que vous feriez confirmer par le client avant de lancer la reprise en
  réel.

Quelques phrases suffisent. Nous ne cherchons pas un rapport, mais à comprendre
vos arbitrages sans avoir à les deviner dans le code.

---

## Précisions

Le schéma, les modèles et l'architecture sont modifiables, y compris en
repartant de zéro si vous jugez le code existant irrécupérable. Dites-nous
simplement pourquoi.

Les gems aussi : `roo` est une suggestion, pas une contrainte.

Bon courage.