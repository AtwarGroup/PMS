// Preserve notification/profile links while opening the shared library workspace.
const params=new URLSearchParams(location.search);params.set('view','requests');
location.replace('index.html?'+params.toString());
