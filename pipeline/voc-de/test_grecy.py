import spacy
nlp = spacy.load("grc_proiel_trf")

text = "καὶ πρὶν μὲν ἐν κακοῖσι κειμένην ὅμως ἐλπίς μʼ ἀεὶ προσῆγε σωθέντος τέκνου ἀλκήν τινʼ εὑρεῖν κἀπικούρησιν δόμον"

doc = nlp(text)

for token in doc:
    print(f'{token.text}, lemma: {token.lemma_} pos:{token.pos_}')
