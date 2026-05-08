with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Zoek waar de _TrainerCard wordt aangeroepen en voeg een FutureBuilder toe
if 'FutureBuilder' not in content:
    # Dit is complexer - we moeten de state management aanpassen
    print("⚠️ Handmatige aanpassing nodig in dashboard_screen.dart")
    print("Zoek naar de _TrainerCard aanroep en voeg een FutureBuilder toe")
else:
    print("✅ FutureBuilder al aanwezig")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
