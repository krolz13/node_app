const express = require('express');
const path = require('path');
const os = require('os');
const app = express();

// Middleware
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

// Routes/API
app.get('/api/status', (req, res) => {
  // Calculate system uptime
  const uptimeSeconds = os.uptime();
  const days = Math.floor(uptimeSeconds / (3600 * 24));
  const hours = Math.floor((uptimeSeconds % (3600 * 24)) / 3600);
  const minutes = Math.floor((uptimeSeconds % 3600) / 60);
  
  res.json({
    status: "Healthy",
    version: "1.0.0",
    environment: process.env.NODE_ENV || "production",
    platform: os.platform(),
    release: os.release(),
    arch: os.arch(),
    hostname: os.hostname(),
    uptime: `${days}d ${hours}h ${minutes}m`,
    cpuCount: os.cpus().length,
    freeMemory: `${(os.freemem() / 1024 / 1024 / 1024).toFixed(2)} GB`,
    totalMemory: `${(os.totalmem() / 1024 / 1024 / 1024).toFixed(2)} GB`,
    deployTime: new Date().toISOString(),
    pipelineId: process.env.CI_PIPELINE_ID || "local-dev",
    commitSha: process.env.CI_COMMIT_SHORT_SHA || "dev-commit"
  });
});

app.get('/api/todos', (req, res) => {
  res.json([
    { id: 1, text: 'Provision Proxmox Debian 12 VMs', completed: true },
    { id: 2, text: 'Configure GitLab CI/CD runner', completed: false },
    { id: 3, text: 'Dockerize Node.js application', completed: true },
    { id: 4, text: 'Setup automatic production deployment', completed: false }
  ]);
});

// Serve HTML Pages
app.get('/about', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'about.html'));
});

// Catch-all route to serve dashboard
app.get('*splat', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

module.exports = app;