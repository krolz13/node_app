const express = require('express');
const path = require('path');
const app = express();
const port = process.env.PORT || 3000;

// Serve static files (add public/ folder for CSS/JS/images later)
app.use(express.static('public'));
app.use(express.json());

// Routes/pages
app.get('/', (req, res) => {
  res.send(`
    <h1>Welcome to My Node App</h1>
    <a href="/about">About</a> | <a href="/todos">Todos</a>
    <p>Deployed via Proxmox CI/CD pipeline!</p>
  `);
});

app.get('/about', (req, res) => {
  res.send(`
    <h1>About</h1>
    <p>Simple app for homelab DevOps practice. GitHub → GitLab → Docker.</p>
    <a href="/">Home</a>
  `);
});

app.get('/todos', (req, res) => {
  res.json([{ id: 1, text: 'Learn Proxmox' }, { id: 2, text: 'Deploy Node app' }]);
});

app.listen(port, () => {
  console.log(`App running at http://localhost:${port}`);
});