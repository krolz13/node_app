const app = require('./server');
const port = process.env.PORT || 3000;

app.listen(port, () => {
  console.log(`=============================================`);
  console.log(`🚀 DevOps Node App is running on port ${port}`);
  console.log(`👉 Access URL: http://localhost:${port}`);
  console.log(`=============================================`);
});
